#!/usr/bin/env python3
"""Download the desktop's exact model for offline simulator integration tests."""
import hashlib
import pathlib
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
DESTINATION = ROOT / 'GameLingoTests' / 'Fixtures' / 'en_ar'
PACKAGE = ROOT / '.build' / 'translate-en_ar-1_0.argosmodel'
DIGEST = 'e2a6e84337f7ebbb55f9dc61dcba3a861c0d786ae5a46fa198fd8d6473f5c775'
SIZE = 88502631
PACKAGE.parent.mkdir(parents=True, exist_ok=True)
if not PACKAGE.exists():
    with urllib.request.urlopen('https://argos-net.com/v1/translate-en_ar-1_0.argosmodel', timeout=60) as response, PACKAGE.open('wb') as output:
        while chunk := response.read(256 * 1024):
            output.write(chunk)
            if output.tell() > SIZE:
                raise RuntimeError('Unexpected model download size')
if PACKAGE.stat().st_size != SIZE or hashlib.sha256(PACKAGE.read_bytes()).hexdigest() != DIGEST:
    raise RuntimeError('Model SHA-256 mismatch')
with zipfile.ZipFile(PACKAGE) as archive:
    for name in ('model/model.bin', 'model/shared_vocabulary.txt', 'sentencepiece.model', 'metadata.json', 'README.md'):
        target = DESTINATION / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(archive.read('en_ar/' + name))
print('Verified exact EN-AR package for offline XCTest fixtures')
