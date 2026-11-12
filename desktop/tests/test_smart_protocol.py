import threading
import time
from gamelingo import pipeline
from gamelingo.capture import Frame
from gamelingo.diagnostics import sample_image
from gamelingo.ocr import Reading

def test_source_disappearance_preserves_tv_until_explicit_stop(tmp_path,monkeypatch):
    shown=threading.Event()
    class Source:
        def read(self):return Frame(sample_image("blank" if shown.is_set() else "text"),time.time(),"test")
    class OCR:
        def __init__(self,_):pass
        async def read(self,_):return [] if shown.is_set() else [Reading("Read me",(.2,.5,.6,.1))]
    class Engine:
        def __init__(self,_):pass
        def translate(self,_):return "اقرأ النص"
    monkeypatch.setattr(pipeline,"WindowsOCR",OCR)
    monkeypatch.setattr(pipeline,"ArgosTranslationProvider",Engine)
    messages=[]
    def publish(m):
        messages.append(m)
        if m["type"]=="subtitle_show":shown.set()
    p=pipeline.Pipeline(Source(),(0,0,1,1),8,tmp_path,tmp_path/"db",{},"test",lambda *_:None,publish)
    p.thread.start()
    try:
        assert shown.wait(4);time.sleep(.9)
        assert not any(m["type"]=="subtitle_clear" for m in messages)
    finally:p.stop();p.thread.join(5)
    assert messages[-1]["type"]=="subtitle_clear"
