import numpy as np
from PIL import Image,ImageDraw,ImageFont
from gamelingo.performance import Scheduler
from gamelingo.display_settings import validate,preset,DEFAULTS

def test_settings_bounds_and_duration():
    v=validate(dict(x=999999,y=-999999,max_entries=9,min_seconds=8,max_seconds=4,text_color="invalid"))
    assert v["x"]==7680 and v["y"]==-4320 and v["max_entries"]==3
    assert v["max_seconds"]==8 and v["text_color"]=="#FFFFFF"
    assert preset("Classic")["background"] is False
    assert preset("Cinema")["background"] is True

def test_mode_hysteresis_and_recovery():
    s=Scheduler("Performance")
    for n in range(5):s.load(95,20+n)
    assert s.rate==7
    for n in range(10):s.load(40,50+n)
    assert s.rate==8
    s.automatic=False;s.mode="Economy";s.load(100,100);assert s.rate==2

def test_subtitle_aware_change_detection_on_moving_background():
    s=Scheduler();calls=[]
    for i in range(12):
        a=np.full((180,700),40+i*2,dtype=np.uint8)
        img=Image.fromarray(a)
        ImageDraw.Draw(img).text((220,60),"Follow me to the gate.",font=ImageFont.truetype("arial.ttf",26),fill=245)
        calls.append(s.should_read(img,i*.1))
    assert sum(calls)<len(calls)/2
    ImageDraw.Draw(img).rectangle((0,0,700,180),fill=45)
    ImageDraw.Draw(img).text((220,60),"Take the key.",font=ImageFont.truetype("arial.ttf",26),fill=245)
    assert s.should_read(img,1.21)

