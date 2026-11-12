import sys,time,tempfile,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"desktop"))
import psutil
from gamelingo.pipeline import Pipeline
from gamelingo.diagnostics import SampleSource
from gamelingo.performance import Scheduler
from gamelingo.storage import data_root
p=psutil.Process();rows=[];errors=[]
seconds=int(sys.argv[2]) if len(sys.argv)>2 else 120
with tempfile.TemporaryDirectory() as tmp:
    task=Pipeline(SampleSource(),(.04,.54,.92,.44),4,data_root()/"models",Path(tmp)/"cache.sqlite",{},"test",
                  lambda k,v:errors.append(str(v)) if k=="error" else None,lambda _:None,subtitles_only=True)
    task.scheduler=Scheduler("Balanced",False);task.thread.start()
    start=time.monotonic();p.cpu_percent()
    while time.monotonic()-start<seconds:
        time.sleep(1);rows.append(dict(seconds=round(time.monotonic()-start),rss_mb=p.memory_info().rss/1048576,cpu_percent=p.cpu_percent()/psutil.cpu_count(),threads=p.num_threads()))
    task.stop();task.thread.join(10)
    data=dict(duration_seconds=seconds,warmup_seconds=10,samples=rows,metrics=task.metrics,errors=errors,finished=not task.thread.is_alive())
    Path(sys.argv[1]).write_text(json.dumps(data,indent=2))
    print(f"{seconds}-second static test",len(errors),"errors","warm RAM",round(rows[10]["rss_mb"],1),"final",round(rows[-1]["rss_mb"],1))

