import ctypes
import json
import os
import tempfile
from pathlib import Path
from ctypes import wintypes

def data_root():
    return Path(os.environ["LOCALAPPDATA"]) / "GameLingo"

def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as out:
        name = out.name
        out.write(data)
    try:
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)

def settings(root):
    try:
        return json.loads((root / "settings.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}

def save(root, config):
    atomic_write(root / "settings.json", json.dumps(config, ensure_ascii=False, indent=2).encode())

class Blob(ctypes.Structure):
    _fields_ = [("size", wintypes.DWORD), ("data", ctypes.c_void_p)]

def _dpapi(data, method):
    buf = ctypes.create_string_buffer(data)
    inp = Blob(len(data), ctypes.cast(buf, ctypes.c_void_p))
    out = Blob()
    ok = method(ctypes.byref(inp), None, None, None, None, 1, ctypes.byref(out))
    if not ok:
        raise ctypes.WinError()
    try:
        return ctypes.string_at(out.data, out.size)
    finally:
        ctypes.windll.kernel32.LocalFree(ctypes.c_void_p(out.data))

def protect(data):
    return _dpapi(data, ctypes.windll.crypt32.CryptProtectData)

def unprotect(data):
    return _dpapi(data, ctypes.windll.crypt32.CryptUnprotectData)

