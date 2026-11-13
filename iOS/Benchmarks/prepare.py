#!/usr/bin/env python3
"""Download checksum-pinned, optional Windows CPU benchmark assets only.
This does not install a translation engine into GameLingo or modify its model.
"""
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request
import zipfile

HERE = Path(__file__).resolve().parent
BUILD = HERE.parent / '.build/context-benchmark'
BUILD.mkdir(parents=True, exist_ok=True)
assets = json.loads((HERE / 'assets.json').read_text(encoding='utf-8'))
for key, filename in [('llama_zip', 'llama.zip'), ('qwen', 'qwen.gguf')]:
    target = BUILD / filename
    if not target.exists():
        part = target.with_suffix('.download')
        with urllib.request.urlopen(assets[key]['url'], timeout=120) as source, part.open('wb') as output:
            shutil.copyfileobj(source, output)
        part.replace(target)
    with target.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    assert digest == assets[key]['sha256'], f'{filename}: checksum mismatch'
    print(f'{filename}: verified')

destination = (BUILD / 'llama').resolve()
with zipfile.ZipFile(BUILD / 'llama.zip') as archive:
    for member in archive.infolist():
        resolved = (destination / member.filename).resolve()
        assert resolved.is_relative_to(destination), 'Unsafe archive member'
        assert member.external_attr >> 16 & 0o170000 != 0o120000, 'Symlink not allowed'
    archive.extractall(destination)
assert (destination / 'llama-server.exe').is_file()
print('Optional benchmark assets prepared; no application files changed.')
