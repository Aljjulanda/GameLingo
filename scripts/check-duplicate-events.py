"""Reproduce short OCR correction and genuine reappearance against either checkout."""
import sys,time,tempfile,json,threading
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1]).resolve()/'desktop'))
from PIL import Image
from gamelingo import pipeline
from gamelingo.capture import Frame
from gamelingo.ocr import Reading
clock=[None];stage=[0];messages=[];errors=[]
class Source:
 def read(self):
  now=time.monotonic()
  if clock[0] is None:clock[0]=now
  t=now-clock[0];stage[0]=0 if t<.5 else 1 if t<1 else 2 if t<1.8 else 3
  return Frame(Image.new('L',(400,160),40+stage[0]),time.time(),'synthetic')
class OCR:
 def __init__(self,_):pass
 async def read(self,_):
  line=["Let's go.",'Lets go!','',"Let's go."][stage[0]]
  return [Reading(line,(.2,.6,.6,.1))] if line else []
class Engine:
 def __init__(self,_):pass
 def translate(self,s):return 'لنذهب!' if "'" in s else 'لنذهب.'
class Scheduler:
 rate=8;changed=False
 def should_read(self,*_):return True
 def interval(self,*_):return .125
 def activity(self,*_):pass
pipeline.WindowsOCR=OCR;pipeline.ArgosTranslationProvider=Engine
with tempfile.TemporaryDirectory() as t:
 p=pipeline.Pipeline(Source(),(0,0,1,1),8,Path(t),Path(t)/'db',{},'fixture',lambda k,v:errors.append(v) if k=='error' else None,messages.append)
 p.scheduler=Scheduler();p.thread.start();time.sleep(2.5);p.stop();p.thread.join(5)
shows=[m for m in messages if m['type'] in ('subtitle_show','subtitle_update')]
r=dict(events=[{'type':m['type'],'id':m['id'],'translated':m['translated']} for m in shows],errors=errors,
 correction_reuses_id=len(shows)==3 and shows[0]['id']==shows[1]['id'],repeat_has_new_id=len(shows)==3 and shows[1]['id']!=shows[2]['id'])
Path(sys.argv[2]).write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(r,ensure_ascii=True))
