"""Bounded identity for the currently observed dialogue, independent of translation."""
import re,uuid
from difflib import SequenceMatcher
from .tracking import words,still_visible_prefix

def same_dialogue(before,after):
    a,b=(words(re.sub("['’`]",'',s)) for s in (before,after))
    if not a or not b:return False
    if a==b:return True
    # Apostrophe/spacing/punctuation corrections, including short utterances.
    if ''.join(a)==''.join(b):return True
    if re.findall(r'[+-]?\d+(?:[.,]\d+)*',before)!=re.findall(r'[+-]?\d+(?:[.,]\d+)*',after):return False
    if still_visible_prefix(before,after) or still_visible_prefix(after,before):return True
    # A briefly lost speaker label or word must not append another translation.
    # Require ordered retained words, a substantial common sentence, and never
    # treat a missing negation as OCR noise. The caller also bounds time/position.
    short,long=sorted((a,b),key=len)
    if len(short)>=3 and 0<len(long)-len(short)<=2 and len(short)/len(long)>=.72:
        at=0;missing=[]
        for token in long:
            if at<len(short) and token==short[at]:at+=1
            else:missing.append(token)
        if at==len(short) and not set(missing)&{'no','not','never','dont','cannot','cant','wont','without'}:
            return True
    if len(a)!=len(b):return False
    changed=[(x,y) for x,y in zip(a,b) if x!=y]
    if len(changed)!=1:return False
    x,y=changed[0]
    # Conservative internal glyph correction, not a whole changed word/command.
    return (min(len(x),len(y))>=5 and x[0]==y[0] and x[-1]==y[-1]
            and SequenceMatcher(None,x,y).ratio()>=.8
            and SequenceMatcher(None,''.join(a),''.join(b)).ratio()>=.9)

class DialogueEvents:
    def __init__(self):
        self.prefix=uuid.uuid4().hex[:12];self.serial=0;self.id=None;self.text='';self.box=None;self.last_seen=0.
    def observe(self,text,box,now):
        adjacent=self.box is None or (abs((box[0]+box[2]/2)-(self.box[0]+self.box[2]/2))<.2 and abs(box[1]-self.box[1])<.12)
        update=bool(self.id and now-self.last_seen<=1.5 and adjacent and same_dialogue(self.text,text))
        if not update:
            self.serial+=1;self.id=f'{self.prefix}-{self.serial}'
        self.text=text;self.box=box;self.last_seen=now
        return self.id,update
    def absent(self):
        self.id=None;self.text='';self.box=None
