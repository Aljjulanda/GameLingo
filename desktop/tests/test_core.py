import asyncio
import time
from pathlib import Path
import pytest
from PIL import Image, ImageDraw, ImageFont
from gamelingo.capture import crop, ImageFileSource
from gamelingo.models import install
from gamelingo.ocr import WindowsOCR
from gamelingo.tracking import Tracker
from gamelingo.translation import Memory, normalized, ArgosTranslationProvider
from gamelingo.storage import data_root, save, settings

class Echo:
    def translate(self,s):return "T("+s+")"

def test_cache_versions_and_glossary(tmp_path):
    db=Memory(tmp_path/"cache")
    assert normalized(" A\n B ")=="A B"
    assert db.resolve("Go to Gate",Echo(),{"Gate":"البوابة"})=="T(Go to) البوابة"
    assert db.resolve("Go to Gate",Echo(),{"Gate":"البوابة"})=="T(Go to) البوابة"
    assert db.hits==1
    db.close();db=Memory(tmp_path/"cache");db.resolve("Go to Gate",Echo(),{"Gate":"البوابة"});assert db.hits==1
    db.resolve("Go to Gate",Echo(),{"Gate":"البوابة"},version="new"); assert db.hits==1
    db.close()

def test_tracker():
    t=Tracker(); assert t.observe("Collect 10 coins",0)==(1,"Collect 10 coins")
    assert t.observe("Collect 10 coins",.2) is None
    assert t.observe("Collect 11 coins",.3)[0]==2
    assert t.observe("",.4) is None
    assert t.observe("",1.)==(3,"")
    assert t.observe("No",1.1)==(4,"No")
    assert t.observe("Go",1.2)==(5,"Go")

def test_settings(tmp_path):
    save(tmp_path,{"profile":"لعبة"});assert settings(tmp_path)=={"profile":"لعبة"}

def test_missing_model_and_untrusted_asset(tmp_path):
    with pytest.raises(FileNotFoundError):ArgosTranslationProvider(tmp_path)
    archive=tmp_path/"bad";archive.write_bytes(b"bad")
    with pytest.raises(ValueError):install(tmp_path/"models",archive)

def test_frame_ocr_translation(tmp_path):
    pic=Image.new("RGB",(760,240),"#20363a")
    ImageDraw.Draw(pic).text((40,146),"Open the door.",font=ImageFont.truetype("arial.ttf",42),fill="white")
    f=tmp_path/"synthetic.png";pic.save(f)
    frame=ImageFileSource(f).read();assert frame.dimensions==(760,240)
    assert abs(time.time()-frame.timestamp)<1
    region=crop(frame.image,(0,.5,1,.5))
    text=asyncio.run(WindowsOCR("en").read(region))
    assert text[0].text=="Open the door."
    assert all(0<=v<=1 for v in text[0].box)
    engine=ArgosTranslationProvider(data_root()/"models")
    assert "الباب" in engine.translate(text[0].text)
    with pytest.raises(ValueError):crop(frame.image,(0,.5,1,2))

