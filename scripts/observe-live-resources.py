"""Passive live process/resource observation, no video, text or input capture."""
import sys,time,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'desktop'))
import psutil
from gamelingo.gpu_metrics import GPU
seconds=int(sys.argv[2]);main=psutil.Process(int(sys.argv[3]));gpu=GPU();rows=[];objects={main.pid:main};start=time.monotonic();psutil.cpu_percent();last_scan=0;stream=False
main.cpu_percent()
while time.monotonic()-start<seconds:
 now=time.monotonic()
 if now-last_scan>=5:
  last_scan=now;stream=False
  for p in psutil.process_iter(['name']):
   if (p.info['name'] or '').lower()=='chiaki.exe':
    if p.pid not in objects:objects[p.pid]=p;p.cpu_percent()
    try:stream|=any(s.raddr and s.raddr.port==9295 and s.status=='ESTABLISHED' for s in p.net_connections(kind='tcp4'))
    except psutil.Error:pass
 time.sleep(1);g=gpu.sample();row=dict(seconds=round(time.monotonic()-start),total_cpu=psutil.cpu_percent(),total_gpu=g['total'] if g else None,remote_play_control_connected=stream,processes={})
 for pid,p in list(objects.items()):
  try:row['processes'][str(pid)]=dict(name=p.name(),cpu=p.cpu_percent()/psutil.cpu_count(),rss_mb=p.memory_info().rss/1048576,gpu=g['processes'].get(pid,0) if g else None,threads=p.num_threads())
  except psutil.Error:objects.pop(pid,None)
 rows.append(row)
 # Progress is aggregate metrics only and is bounded by this finite observation.
 if len(rows)%15==0:Path(sys.argv[1]).write_text(json.dumps({'target_seconds':seconds,'complete':False,'main_pid':main.pid,'samples':rows},indent=2))
gpu.close();Path(sys.argv[1]).write_text(json.dumps({'target_seconds':seconds,'complete':True,'main_pid':main.pid,'samples':rows},indent=2));print('Passive samples',len(rows),'stream connected samples',sum(r['remote_play_control_connected'] for r in rows))
