"""Validated configuration shared by the desktop controls and the TV."""
import time
DEFAULTS = dict(font_family="sans-serif",font_size=25,font_weight=400,bold=False,
 text_color="#FFFFFF",text_opacity=100,outline=True,outline_color="#000000",outline_width=2,
 shadow=True,shadow_color="#000000",shadow_opacity=80,shadow_x=0,shadow_y=2,shadow_blur=2,
 line_spacing=3,alignment="center",max_width=88,wrap=True,background=True,
 background_color="#000000",background_opacity=65,padding_x=18,padding_y=8,radius=9,
 border=False,border_color="#FFFFFF",border_width=1,x=0,y=0,margin=24,
 adaptive=True,reading_speed=13,min_seconds=4,max_seconds=8,fixed_seconds=5,
 max_entries=3,max_height=25,older_opacity=85,spacing=10)
BOUNDS = dict(font_size=(10,100),font_weight=(100,900),text_opacity=(0,100),
 outline_width=(0,12),shadow_opacity=(0,100),shadow_x=(-40,40),shadow_y=(-40,40),shadow_blur=(0,20),
 line_spacing=(0,40),max_width=(10,100),background_opacity=(0,100),padding_x=(0,100),
 padding_y=(0,100),radius=(0,80),border_width=(0,12),x=(-7680,7680),y=(-4320,4320),
 margin=(0,200),reading_speed=(1,60),min_seconds=(1,30),max_seconds=(1,60),
 fixed_seconds=(1,60),max_entries=(1,3),max_height=(10,90),older_opacity=(0,100),spacing=(0,80))
def validate(values):
    import re
    result=DEFAULTS.copy()
    for key,default in DEFAULTS.items():
        value=values.get(key,default)
        if isinstance(default,bool): result[key]=bool(value)
        elif key in BOUNDS:
            low,high=BOUNDS[key];result[key]=max(low,min(high,float(value)))
        elif key.endswith("color"):
            if re.fullmatch(r"#[0-9a-fA-F]{6}",str(value)):result[key]=value
        else:result[key]=str(value)[:80]
    result["max_seconds"]=max(result["min_seconds"],result["max_seconds"])
    result["revision"]=int(values.get("revision",0))
    return result

def preset(name):
    s=DEFAULTS.copy()
    if name=="Classic":s.update(background=False,outline=True,outline_width=2)
    if name=="Cinema":s.update(background=True,background_opacity=65,outline=False)
    if name=="Gaming":s.update(bold=True,outline_width=3,background_opacity=75)
    if name=="Minimal":s.update(background=False,outline=False,shadow=True)
    return s

