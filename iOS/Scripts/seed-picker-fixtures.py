#!/usr/bin/env python3
"""Seed explicitly synthetic UI fixtures into the selected CI simulator only."""
import hashlib
import json
import pathlib
import sqlite3
import subprocess
import sys
import tempfile
import zipfile

device, app = sys.argv[1:]
subprocess.run(['xcrun', 'simctl', 'install', device, app], check=True)
container = pathlib.Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, 'dev.gamelingo.ios', 'data'], text=True).strip())
assert '/CoreSimulator/Devices/' in str(container)
documents = container / 'Documents'
documents.mkdir(exist_ok=True)
root = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root.parent / 'tools/pack_converter'))
import convert

pairs = [{'source': 'Move now.', 'target': 'تحرك الآن.'}]
raw = json.dumps({'game_id': 'picker-fixture', 'game_title': 'Synthetic Picker Game', 'attribution': 'Original synthetic fixture', 'license': 'Test only', 'entries': pairs}, ensure_ascii=False).encode()
fixtures = {
    'json': raw, 'unknownformat': raw,
    'xml': '<localization game_id="picker-xml"><entry><source>Move now.</source><target>تحرك الآن.</target></entry></localization>'.encode(),
    'csv': 'source,target\nMove now.,تحرك الآن.\n'.encode(),
    'txt': 'source\ttarget\nMove now.\tتحرك الآن.\n'.encode(),
    'rar': bytes.fromhex('526172211a070100'), '7z': bytes.fromhex('377abcaf271c'),
}
pe = bytearray(68)
pe[:2] = b'MZ'
pe[60] = 64
pe[64:68] = b'PE\0\0'
fixtures['exe'] = bytes(pe)
with tempfile.TemporaryDirectory() as temporary:
    folder = pathlib.Path(temporary)
    db = folder / 'translations.sqlite'
    connection = sqlite3.connect(db)
    connection.execute(convert.SCHEMA)
    for sql in convert.INDEXES.values(): connection.execute(sql)
    connection.execute('PRAGMA user_version=1')
    connection.execute('INSERT INTO entries VALUES (?,?,?,?,?,?,?,?,?)', ('1','1','Move now.','move now','تحرك الآن.','general','synthetic','[]',1))
    connection.commit()
    connection.close()
    digest = lambda value: hashlib.sha256(value).hexdigest()
    manifest = dict(format_version=1, schema_version=1, game_id='picker-fixture', game_title='Synthetic Picker Game', source_language='en', target_language='ar', pack_version='1', record_count=1, usable_count=1, categories=['general'], attribution='Original synthetic fixture', permission='Test only', built_at='2026-11-14', arabic_order='logical', database_sha256=digest(db.read_bytes()), speaker_names=[], coverage='partial')
    manifest_raw = json.dumps(manifest).encode()
    pack = folder / 'fixture.glpack'
    with zipfile.ZipFile(pack, 'w') as archive:
        archive.writestr('manifest.json', manifest_raw)
        archive.writestr('translations.sqlite', db.read_bytes())
        archive.writestr('checksums.json', json.dumps({'manifest.json': digest(manifest_raw), 'translations.sqlite': digest(db.read_bytes())}))
    fixtures['glpack'] = pack.read_bytes()
    zipped = folder / 'fixture.zip'
    with zipfile.ZipFile(zipped, 'w') as archive: archive.writestr('content.custom', raw)
    fixtures['zip'] = zipped.read_bytes()
for ext, data in fixtures.items(): (documents / f'GLPicker-{ext}.{ext}').write_bytes(data)
print(json.dumps({'synthetic_fixture_extensions': sorted(fixtures), 'device': device}))
