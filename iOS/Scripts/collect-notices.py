#!/usr/bin/env python3
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
parts = [(ROOT / 'THIRD_PARTY.md').read_text(encoding='utf-8'), (ROOT / 'LICENSE').read_text(encoding='utf-8')]
half_header = ROOT / '.build/sources/ctranslate2/include/half_float/half.hpp'
if half_header.exists():
    parts.append('CTranslate2 bundled half-float notice\n' + half_header.read_text(encoding='utf-8').split('#ifndef HALF_HALF_HPP', 1)[0])
for root in (ROOT / 'Licenses', ROOT / '.build' / 'sources', ROOT / '.build' / 'native', ROOT.parent / 'licenses'):
    if not root.exists():
        continue
    for path in sorted(root.rglob('*')):
        if not path.is_file() or '.git' in path.parts or len(path.parts) > len(root.parts) + 7:
            continue
        if path.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')) and path.stat().st_size < 150_000:
            parts.append('\n--- ' + str(path.relative_to(root)).replace('\\', '/') + ' ---\n' + path.read_text(encoding='utf-8', errors='replace'))
destination = ROOT / 'GameLingo' / 'Resources' / 'ThirdPartyNotices.txt'
text = '\n'.join(line.rstrip() for line in '\n\n'.join(parts).splitlines()).rstrip() + '\n'
destination.write_text(text, encoding='utf-8', newline='\n')
