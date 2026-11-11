import concurrent.futures
import threading
import time
from pathlib import Path
from gamelingo import pipeline
from gamelingo.capture import CaptureUnavailable, Frame
from gamelingo.diagnostics import sample_image
from gamelingo.ocr import Reading


def test_slow_old_translation_cannot_override_new_frame(tmp_path,monkeypatch):
    entered=threading.Event();release=threading.Event();new_seen=threading.Event()
    out=[];results=[]
    class Source:
        def __init__(self):
            self.old=sample_image("Old");self.new=sample_image("New")
        def read(self):
            return Frame(self.new if entered.is_set() else self.old,time.time(),"synthetic race")
    class Engine:
        def __init__(self,_):pass
        def translate(self,text):
            if text=="Old":
                entered.set();assert release.wait(4)
            return "translated "+text
    class OCR:
        def __init__(self,_):pass
        async def read(self,img):
            if entered.is_set():
                new_seen.set();return [Reading("New",(0,0,.5,.2))]
            return [Reading("Old",(0,0,.5,.2))]
    monkeypatch.setattr(pipeline,"ArgosTranslationProvider",Engine)
    monkeypatch.setattr(pipeline,"WindowsOCR",OCR)
    finished=threading.Event()
    def notify(kind,msg):
        if kind=="result":results.append(msg);finished.set()
    p=pipeline.Pipeline(Source(),(0,0,1,1),8,tmp_path,tmp_path/"db",{},"test",notify,out.append)
    p.thread.start()
    try:
        assert new_seen.wait(4);release.set();assert finished.wait(4)
    finally:
        release.set();p.stop();p.thread.join(5)
    assert [r["source"] for r in results]==["New"]
    assert [m["translated"] for m in out if m["type"]=="subtitle_show"]==["translated New"]
    assert out[-1]["type"]=="subtitle_clear"


def test_repeated_still_does_not_repeat_ocr(tmp_path,monkeypatch):
    counts=dict(ocr=0,translation=0)
    im=sample_image()
    class Source:
        def read(self):return Frame(im,time.time(),"still")
    class OCR:
        def __init__(self,_):pass
        async def read(self,img):
            counts["ocr"]+=1;return [Reading("Wait",(0,0,.5,.2))]
    class Engine:
        def __init__(self,_):pass
        def translate(self,text):
            counts["translation"]+=1;return "انتظر"
    monkeypatch.setattr(pipeline,"WindowsOCR",OCR)
    monkeypatch.setattr(pipeline,"ArgosTranslationProvider",Engine)
    event=threading.Event()
    p=pipeline.Pipeline(Source(),(0,0,1,1),8,tmp_path,tmp_path/"db",{},"test",lambda k,v:event.set() if k=="result" else None,lambda m:None)
    p.thread.start()
    try:
        assert event.wait(4);time.sleep(.5)
    finally:
        p.stop();p.thread.join(5)
    assert counts==dict(ocr=1,translation=1)

