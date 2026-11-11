"""Local evaluation uses an original synthetic image. No desktop pixels or user text are saved."""
import json
import tempfile
import threading
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from .capture import Frame
from .pipeline import Pipeline
from .storage import data_root
import time

def sample_image(line="Open the door.", font_size=42, color="#fcfcfa"):
    im=Image.new("RGB",(960,540),"#19333b")
    draw=ImageDraw.Draw(im)
    draw.rectangle((100,90,410,320),fill="#2c454c")
    draw.rectangle((275,115,374,320),fill="#14282d")
    draw.ellipse((345,220,353,228),fill="#aac8a0")
    draw.rounded_rectangle((115,361,846,474),12,fill="#12252b")
    draw.multiline_text((146,380),line,font=ImageFont.truetype("arial.ttf",font_size),fill=color,spacing=4)
    return im

class SampleSource:
    def __init__(self):self.image=sample_image()
    def read(self):return Frame(self.image,time.time(),"sample")

def self_test(path, window):
    errors=[]; results=[]; messages=[]; done=threading.Event()
    def notice(kind,value):
        if kind=="error":errors.append(str(value));done.set()
        if kind=="result":results.append(value);done.set()
    with tempfile.TemporaryDirectory() as temp:
        pipeline=Pipeline(SampleSource(),(.04,.62,.92,.35),4,data_root()/"models",Path(temp)/"memory.sqlite",
                          {},"Default",notice,messages.append)
        pipeline.thread.start();done.wait(25);pipeline.stop();pipeline.thread.join(15)
    ok=bool(results and "الباب" in results[0]["translated"] and not errors and not pipeline.thread.is_alive())
    report={"pass":ok,"tabs":window.tabs.count(),"fixture":"original synthetic EN image",
            "measured":results[:1],"messages":[x["type"] for x in messages],"errors":errors}
    Path(path).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    return 0 if ok else 1

