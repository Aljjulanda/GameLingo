import hashlib
from concurrent.futures import CancelledError
import json
import re
import sqlite3
import unicodedata
from collections import OrderedDict
from pathlib import Path
from typing import Protocol

from .models import MODEL_ID, ready


def normalized(text: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", text).split())


class TranslationProvider(Protocol):
    def translate(self, text: str) -> str: ...


class ArgosTranslationProvider:
    """Run the Argos EN→AR package directly, one grouped game subtitle per segment."""
    def __init__(self, root: Path):
        if not ready(root):
            raise FileNotFoundError("نموذج الترجمة غير مثبت · English → Arabic model missing")
        import ctranslate2
        import sentencepiece
        folder = root / MODEL_ID
        self.tokenizer = sentencepiece.SentencePieceProcessor(model_file=str(folder / "sentencepiece.model"))
        self.engine = ctranslate2.Translator(str(folder / "model"), device="cpu", compute_type="int8", intra_threads=2)
        self.cancelled = lambda: False

    def translate(self, text: str) -> str:
        pieces = self.tokenizer.encode(text, out_type=str)
        limit = min(256,max(24,2*len(pieces)+12))
        if self.cancelled():
            raise CancelledError()
        result = self.engine.translate_batch([pieces], beam_size=1, max_decoding_length=limit,
                                             callback=lambda _step: self.cancelled())
        if self.cancelled():
            raise CancelledError()
        return self.tokenizer.decode(result[0].hypotheses[0]).strip()


class Memory:
    def __init__(self, path: Path):
        self.db = sqlite3.connect(path, timeout=10)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("CREATE TABLE IF NOT EXISTS memory (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        self.hot = OrderedDict()
        self.hits = self.requests = 0

    def resolve(self, text, engine, glossary, profile="Default", source="en", target="ar", version=MODEL_ID):
        text = normalized(text)
        key = hashlib.sha256(json.dumps([text, source, target, version, glossary, profile], sort_keys=True,
                                        ensure_ascii=False).encode()).hexdigest()
        self.requests += 1
        value = self.hot.get(key)
        if value is None:
            row = self.db.execute("SELECT value FROM memory WHERE key=?", (key,)).fetchone()
            value = row[0] if row else None
        if value is None:
            # Whole-line overrides preserve grammar. Split only around explicitly protected terms.
            terms = sorted((k for k in glossary if k.strip()), key=len, reverse=True)
            if text in glossary:
                value = glossary[text]
            elif terms:
                pattern = r"(?<!\w)(" + "|".join(map(re.escape, terms)) + r")(?!\w)"
                value = " ".join(glossary[s] if s in glossary else engine.translate(s.strip())
                                 for s in re.split(pattern, text) if s.strip())
            else:
                value = engine.translate(text)
            if not value:
                raise ValueError("Empty translation")
            with self.db:
                self.db.execute("INSERT OR REPLACE INTO memory VALUES (?, ?)", (key, value))
        else:
            self.hits += 1
        self.hot[key] = value
        self.hot.move_to_end(key)
        if len(self.hot) > 256:
            self.hot.popitem(last=False)
        return value

    def close(self):
        self.db.close()

