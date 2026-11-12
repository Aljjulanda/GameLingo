"""Compare owned conversions/OCR on exactly the same live frame; save metrics only."""
import sys,time,queue,threading,asyncio,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'desktop'))
from windows_capture import WindowsCapture
from gamelingo.capture import ChiakiStreamSource,crop
from gamelingo.frame_conversion import owned_image
from gamelingo.ocr import WindowsOCR
from gamelingo.storage import data_root,settings
from gamelingo.tracking import words
cfg=settings(data_root());profile=cfg['profiles'][cfg['profile']];roi=tuple(map(float,profile.get('recognition',{}).get('roi','.16,.65,.68,.28').split(',')))
p=data_root()/'clients/chiaki-ng-1.10.1/chiaki-ng-Win/chiaki.exe';source=ChiakiStreamSource(p);source.detect()
if not source.stream:raise SystemExit('No existing stream')
needed=threading.Event();frames=queue.Queue(maxsize=1)
cap=WindowsCapture(window_hwnd=source.stream.hwnd.value,cursor_capture=False)
@cap.event
def on_frame_arrived(frame,_control):
 if not needed.is_set():return
 needed.clear();t=time.perf_counter();old=owned_image(frame.frame_buffer,frame.width,frame.height,'RGB');middle=time.perf_counter();new=owned_image(frame.frame_buffer,frame.width,frame.height,'L');end=time.perf_counter()
 if frames.empty():frames.put((old,new,frame.width,frame.height,(middle-t)*1000,(end-middle)*1000))
@cap.event
def on_closed(*_):pass
ctl=cap.start_free_threaded()
async def check():
 ocr=WindowsOCR();rows=[]
 for i in range(8):
  needed.set();old,new,w,h,ot,nt=frames.get(timeout=5)
  a=await ocr.read(crop(old,roi).convert('L'));b=await ocr.read(crop(new,roi).convert('L'))
  x=words(' '.join(r.text for r in a));y=words(' '.join(r.text for r in b))
  rows.append(dict(native_size=[w,h],output_size=list(new.size),old_ms=ot,new_ms=nt,old_words=len(x),new_words=len(y),equal_words=x==y))
  await asyncio.sleep(.6)
 return rows
try:rows=asyncio.run(check())
finally:ctl.stop()
Path(sys.argv[1]).write_text(json.dumps({'same_frame_pairs':rows,'no_images_or_dialogue_saved':True},indent=2));print('paired',len(rows),'agree',sum(r['equal_words'] for r in rows),'nonempty',sum(r['old_words']>0 for r in rows))
