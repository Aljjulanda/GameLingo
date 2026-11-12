"""Measure the same executable window fixture before/after, without gameplay storage."""
import json,subprocess,sys,time
from pathlib import Path
import psutil
exe=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve()
p=subprocess.Popen([str(exe),"--window-test",str(out)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
proc=psutil.Process(p.pid);proc.cpu_percent();samples=[]
while p.poll() is None:
    time.sleep(.5)
    try:samples.append(dict(cpu_percent=proc.cpu_percent()/psutil.cpu_count(),rss_mb=proc.memory_info().rss/1048576))
    except psutil.Error:break
p.wait(timeout=10)
data=json.loads(out.read_text("utf8"))
data["process_samples"]=samples
data["process_cpu_mean_percent"]=sum(x["cpu_percent"] for x in samples)/max(1,len(samples))
data["process_ram_peak_mb"]=max((x["rss_mb"] for x in samples),default=0)
out.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf8")
print(exe.parent.name,"exit",p.returncode,"missed",data.get("missed"),"CPU",round(data["process_cpu_mean_percent"],1),"peak MB",round(data["process_ram_peak_mb"],1))

