"""Cheap spatial/structural gates. Windows OCR does not provide confidence scores."""
import re
from .tracking import dialogue_block, words

DEFAULT_ROI = (.16, .65, .68, .28)
CONTEXT_TERMS = {"search", "interact", "pick up", "open", "talk", "examine", "use", "climb"}
MENU_TERMS = {"settings", "options", "inventory", "resume", "resume game", "load game",
              "save game", "new game", "quit", "quit game", "main menu", "graphics",
              "audio", "controls", "objectives", "equipment", "skills", "map"}

def term(text): return " ".join(re.findall(r"\w+",text.casefold()))

def valid_roi(value):
    try:
        x,y,w,h = map(float,value)
        return (x,y,w,h) if 0<=x<1 and 0<=y<1 and w>0 and h>0 and x+w<=1.000001 and y+h<=1.000001 else None
    except (ValueError,TypeError): return None

class DialogueFilter:
    def __init__(self, strictness="Balanced"):
        self.strictness=strictness; self.previous=();self.pending=False
    def select(self, readings):
        # Dense rows and navigation terms are menu structure, even inside a ROI.
        menu=sum(term(r.text) in MENU_TERMS for r in readings)
        if menu>=2 or len(readings)>=5:
            self.previous=();self.pending=False; return []
        candidates=[]
        for r in readings:
            x,y,w,h=r.box; tokens=words(r.text); key=term(r.text)
            if key in MENU_TERMS or key in CONTEXT_TERMS or re.match(r"^(hp|ammo|fps|xp|level)\s*\d",key): continue
            if re.match(r"^(press|hold|tap)\s+",key) or not tokens: continue
            # Location and glyph geometry carry the decision, including short lines.
            if .12<=x+w/2<=.88 and .018<=h<=.55 and sum(c.isalpha() for c in r.text)>=2:
                candidates.append(r)
        selected=dialogue_block(candidates)
        signature=tuple(words(" ".join(r.text for r in selected)))
        reliable=bool(selected) and all(abs(r.box[0]+r.box[2]/2-.5)<=.22 for r in selected)
        accept=reliable or signature==self.previous
        if self.strictness=="Strict": accept=bool(signature) and signature==self.previous
        self.pending=bool(signature) and not accept
        self.previous=signature
        return selected if accept else []

class Presence:
    """Only fresh, valid OCR observations count. Skipped/stale frames do not."""
    def __init__(self): self.empty=0
    def observe(self, readings, valid=True):
        if not valid:return False
        self.empty=0 if readings else self.empty+1
        return self.empty>=2

def map_context(box, roi, video, frame_size, calibrated_size, tv_size, target=(0,0,1,1)):
    """Map only explicitly calibrated, uncropped 16:9 video; otherwise fail closed."""
    if not valid_roi(video) or not valid_roi(target) or not calibrated_size or not tv_size:return None
    fw,fh=frame_size; cw,ch=calibrated_size; tw,th=tv_size
    vx,vy,vw,vh=video; tx,ty,ttw,tth=target
    if min(fw,fh,cw,ch,tw,th)<=0 or abs(fw/fh-cw/ch)>.002:return None
    if abs(vw*fw/(vh*fh)-16/9)>.02 or abs(ttw*tw/(tth*th)-16/9)>.01:return None
    rx,ry,rw,rh=roi; x,y,w,h=box
    x,y,w,h=rx+x*rw,ry+y*rh,w*rw,h*rh
    if x<vx or y<vy or x+w>vx+vw or y+h>vy+vh:return None
    return (tx+(x-vx)/vw*ttw,ty+(y-vy)/vh*tth,w/vw*ttw,h/vh*tth)
