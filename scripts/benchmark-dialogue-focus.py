"""Repeatable generated frames; same interpreter/models, fresh bounded cache per run."""
import argparse,json,statistics,sys,tempfile,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--repo',required=True);p.add_argument('--output',required=True);p.add_argument('--baseline',action='store_true');p.add_argument('--repeat',type=int,default=1)
args=p.parse_args();sys.path.insert(0,str(Path(args.repo).resolve()/'desktop'))
import psutil
from PIL import Image,ImageDraw,ImageFont
from gamelingo.pipeline import Pipeline
from gamelingo.performance import Scheduler
from gamelingo.capture import Frame
from gamelingo.storage import data_root
from gamelingo.tracking import words
sections=[('warm','Ready now.',3),('idle','',5),('rapid','Run!',1.2),('rapid','Wait!',1.2),('rapid','Come here!',1.2),
          ('rapid','Follow me to the gate.',1.2),('rapid','Take the key.',1.2),('rapid','We should leave now.',1.2),
          ('menu','',4),('hud','',4),('stable','Wait for me by the door.',6),('final-empty','',8)]*args.repeat
duration=sum(s[2] for s in sections)
class Source:
    start=None;phase='warm';current='';appeared={}
    def __init__(self):self.font=ImageFont.truetype('arial.ttf',32)
    def read(self):
        now=time.monotonic()
        if self.start is None:self.start=now
        elapsed=now-self.start;until=0
        for phase,line,seconds in sections:
            until+=seconds
            if elapsed<until:break
        self.phase=phase;self.current=line
        if line:self.appeared.setdefault(line,self.start+until-seconds)
        im=Image.new('L',(1280,720),35+int(elapsed*8)%20);d=ImageDraw.Draw(im)
        d.text((20,20),'AMMO '+str(int(elapsed*3)%100),font=self.font,fill=240)
        if phase=='hud':d.text((1080,650),'XP 250',font=self.font,fill=240)
        if phase=='menu':
            for i,t in enumerate(['Resume game','Settings','Inventory','Quit game']):d.text((640,480+i*52),t,anchor='mm',font=self.font,fill=245)
        elif line:d.text((640,562),line,anchor='mm',font=self.font,fill=245)
        return Frame(im,time.time(),'generated-dialogue-fixture')
source=Source();results=[];errors=[];messages=[];rows=[]
def notify(kind,value):
    if kind=='result':
        value=dict(value,phase=source.phase,visible_to_ready_ms=round((time.monotonic()-source.appeared.get(value['source'],time.monotonic()))*1000))
        results.append(value)
    if kind=='error':errors.append(str(value))
own=psutil.Process();own.cpu_percent();psutil.cpu_percent()
chiaki={p.pid:p for p in psutil.process_iter(['name']) if (p.info['name'] or '').lower()=='chiaki.exe'}
for proc in chiaki.values():proc.cpu_percent()
with tempfile.TemporaryDirectory() as tmp:
    extra={} if args.baseline else {'recognition':{'focus':True}}
    roi=(.04,.54,.92,.44) if args.baseline else (.16,.65,.68,.28)
    task=Pipeline(source,roi,4,data_root()/'models',Path(tmp)/'cache.sqlite',{},'benchmark',notify,lambda m:messages.append(m['type']),subtitles_only=True,**extra)
    task.scheduler=Scheduler('Balanced',False);task.thread.start();began=time.monotonic()
    while time.monotonic()-began<duration+1:
        time.sleep(1)
        row=dict(t=round(time.monotonic()-began,1),phase=source.phase,cpu=own.cpu_percent()/psutil.cpu_count(),rss_mb=own.memory_info().rss/1048576,total_cpu=psutil.cpu_percent())
        row['chiaki']={}
        for pid,proc in chiaki.items():
            try:row['chiaki'][str(pid)]=dict(cpu=proc.cpu_percent()/psutil.cpu_count(),rss_mb=proc.memory_info().rss/1048576)
            except psutil.Error:pass
        rows.append(row)
    task.stop();task.thread.join(10)
expected={line for phase,line,_ in sections if phase in ('rapid','stable')}
seen={tuple(words(r['source'])) for r in results}
missed=[s for s in sorted(expected) if tuple(words(s)) not in seen]
false=[r for r in results if r['phase'] in ('menu','hud','idle','final-empty')]
latency=[r['visible_to_ready_ms'] for r in results if r['source'] in expected]
phases={phase:dict(cpu_mean=statistics.mean(r['cpu'] for r in rows if r['phase']==phase),total_cpu_mean=statistics.mean(r['total_cpu'] for r in rows if r['phase']==phase)) for phase in set(r['phase'] for r in rows)}
report=dict(fixture='generated 1280x720, same moving background/captions/HUD/menus; uncached model; no game recordings',baseline=args.baseline,duration_seconds=duration,
    roi=roi,results=results,missed=missed,false_dialogue=false,errors=errors,metrics=task.metrics,process_samples=rows,phases=phases,
    process_cpu_mean=statistics.mean(r['cpu'] for r in rows),system_cpu_mean=statistics.mean(r['total_cpu'] for r in rows),ram_peak_mb=max(r['rss_mb'] for r in rows),
    visible_to_ready_p50_ms=statistics.median(latency) if latency else None,visible_to_ready_max_ms=max(latency,default=None),gpu='unavailable: no reliable counter collected',tv_display_latency='not measured by this desktop-only fixture',finished=not task.thread.is_alive())
Path(args.output).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({k:report[k] for k in ('missed','process_cpu_mean','system_cpu_mean','ram_peak_mb','visible_to_ready_p50_ms','visible_to_ready_max_ms')},ensure_ascii=False),'false',len(false),'OCR',task.ocr_count)
