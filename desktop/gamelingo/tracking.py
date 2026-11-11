import re
from difflib import SequenceMatcher
from .translation import normalized


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
        if text.casefold() == old.casefold() or similar:
            return None
        self.current = text
        self.seq += 1
        return self.seq, text

