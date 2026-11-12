import re
from difflib import SequenceMatcher
from .translation import normalized


def words(text):
    """Ignore typographical jitter when the words and numbers are unchanged."""
    tokens = re.findall(r"[+-]?\d+(?:[.,]\d+)+|[+-]\d+|\w+", normalized(text).casefold())
    # OCR commonly reads an uppercase I as a lowercase l inside longer words.
    return [t.replace("l","i") if len(t)>=4 and t.isalpha() else t for t in tokens]


def still_visible_prefix(old, current):
    before, after = words(old), words(current)
    return len(before) >= 2 and len(after) > len(before) and after[:len(before)] == before


def dialogue_block(readings):
    """Keep adjacent subtitle lines together without appending corner counters."""
    def score_counter(r):
        x,_,w,_=r.box
        return (x+w/2<.15 or x+w/2>.85) and len(r.text.split())<=3 and any(c.isdigit() for c in r.text)
    candidates = [r for r in readings if sum(c.isalpha() for c in r.text) >= 2 and not score_counter(r)]
    if not candidates:
        return []
    def center(r):
        x,y,w,h = r.box
        return x+w/2, y+h/2
    def rank(r):
        cx,cy = center(r)
        return abs(cx-.5) + .25*abs(cy-.65) - .025*min(6,len(r.text.split()))
    anchor = min(candidates,key=rank)
    group = [anchor]
    for line in sorted(candidates,key=lambda r: abs(center(r)[1]-center(anchor)[1])):
        if line is anchor or len(group)>=3:
            continue
        x,y,w,h = line.box
        for near in group:
            a,b,c,d = near.box
            gap = max(y-(b+d), b-(y+h), 0)
            separate_rows = abs(center(line)[1]-center(near)[1]) > .45*min(h,d)
            aligned = abs(center(line)[0]-center(near)[0]) <= .15 or abs(x-a) <= .07
            overlaps = min(x+w,a+c)-max(x,a) > .25*min(w,c)
            if separate_rows and aligned and overlaps and gap <= max(.035,1.35*max(h,d)):
                group.append(line)
                break
    return sorted(group,key=lambda r:(r.box[1],r.box[0]))


class Tracker:
    """One independently tracked ROI. Never collapse number or short-command changes."""
    def __init__(self):
        self.current = ""
        self.seq = 0
        self.empty_since = None

    def observe(self, raw, now, grace=0.55):
        text = normalized(raw)
        if not text:
            if self.empty_since is None:
                self.empty_since = now
            if now - self.empty_since < grace:
                return None
        else:
            self.empty_since = None
        old = self.current
        similar = (len(old) >= 28 and len(text) >= 28 and len(old.split()) == len(text.split())
                   and re.findall(r"\d+", old) == re.findall(r"\d+", text)
                   and SequenceMatcher(None, old.casefold(), text.casefold()).ratio() >= .978)
        if text.casefold() == old.casefold() or (text and old and words(text)==words(old)) or similar:
            return None
        self.current = text
        self.seq += 1
        return self.seq, text

