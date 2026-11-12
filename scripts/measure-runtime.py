"""Measure the same executable window fixture before/after, without gameplay storage."""
import json,subprocess,sys,time
from pathlib import Path
import psutil
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'desktop'))
from gamelingo.gpu_metrics import GPU
exe=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve()
gpu=GPU();psutil.cpu_percent()
p=subprocess.Popen([str(exe),"--window-test",str(out)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
proc=psutil.Process(p.pid);proc.cpu_percent();samples=[]
while p.poll() is None:
    time.sleep(.5)
    try:
        g=gpu.sample()
        samples.append(dict(cpu_percent=proc.cpu_percent()/psutil.cpu_count(),rss_mb=proc.memory_info().rss/1048576,total_cpu=psutil.cpu_percent(),
            process_gpu=g['processes'].get(proc.pid,0) if g else None,total_gpu=g['total'] if g else None))
    except psutil.Error:break
p.wait(timeout=10)
gpu.close()
data=json.loads(out.read_text("utf8"))
data["process_samples"]=samples
data["process_cpu_mean_percent"]=sum(x["cpu_percent"] for x in samples)/max(1,len(samples))
data["process_ram_peak_mb"]=max((x["rss_mb"] for x in samples),default=0)
for key in ('process_gpu','total_gpu','total_cpu'):
    vals=[x[key] for x in samples if x[key] is not None]
    data[key+'_mean']=sum(vals)/len(vals) if vals else None
data['gpu_method']='Windows PDH GPU Engine counters; busiest physical engine, process-specific contribution; samples every 0.5s'
out.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf8")
print(exe.parent.name,"exit",p.returncode,"missed",data.get("missed"),"CPU",round(data["process_cpu_mean_percent"],1),"peak MB",round(data["process_ram_peak_mb"],1))

