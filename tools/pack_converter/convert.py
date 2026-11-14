#!/usr/bin/env python3
"""GameLingo Pack Converter. Data-only adapters; never execute installer code."""
import argparse
import collections
import datetime
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import sqlite3
import struct
import unicodedata
import zipfile

SCHEMA = "CREATE TABLE entries (identifier TEXT NOT NULL, original_id TEXT NOT NULL, source TEXT NOT NULL, normalized TEXT NOT NULL, target TEXT NOT NULL, category TEXT NOT NULL, source_file TEXT NOT NULL, flags TEXT NOT NULL, usable INTEGER NOT NULL)"
INDEXES = {
    'by_exact': 'CREATE INDEX by_exact ON entries(source, category)',
    'by_normalized': 'CREATE INDEX by_normalized ON entries(normalized, category)',
    'by_identifier': 'CREATE INDEX by_identifier ON entries(identifier)',
}
CATEGORIES = {'dialogue', 'menu', 'document', 'general'}
CONTROL = re.compile(r'~[^~\r\n]{1,128}~')
FORMAT_CONTROLS = dict.fromkeys(map(ord, '\u061c\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069'), None)
MAX_TEXT = 16000


def digest(data):
    return hashlib.sha256(data).hexdigest()


def normalize(text):
    text = unicodedata.normalize('NFKC', text.translate(FORMAT_CONTROLS))
    text = text.replace('’', "'").replace('‘', "'").replace('“', '"').replace('”', '"')
    return ' '.join(text.split()).lower().rstrip('.!').rstrip()


def identifier(value):
    if re.fullmatch(r'0x[0-9a-fA-F]{1,8}', value):
        return f'0x{int(value, 16):08X}'
    if not re.fullmatch(r'[A-Za-z0-9_]{1,128}', value):
        raise ValueError('Unsupported localization identifier')
    # RAGE/Jenkins one-at-a-time key, lower-case ASCII; original key is retained.
    result = 0
    for byte in value.lower().encode('ascii'):
        result = (result + byte) & 0xffffffff
        result = (result + (result << 10)) & 0xffffffff
        result ^= result >> 6
    result = (result + (result << 3)) & 0xffffffff
    result ^= result >> 11
    result = (result + (result << 15)) & 0xffffffff
    return f'0x{result:08X}'


def parse_file(path, encoding='utf-8-sig'):
    data = Path(path).read_bytes()
    if len(data) > 64*1024*1024:
        raise ValueError('Localization input exceeds 64 MiB')
    rows, failures = [], []
    if data[:4] == b'2TXG':  # Binary GXT2 table, absolute UTF-8 offsets.
        count = struct.unpack_from('<I', data, 4)[0]
        table_end = 8+count*8
        if count > 500000 or table_end+8 > len(data) or data[table_end:table_end+4] != b'2TXG':
            raise ValueError('Malformed binary GXT2 header')
        end = struct.unpack_from('<I', data, table_end+4)[0]
        if end != len(data):
            raise ValueError('Malformed binary GXT2 length')
        for at in range(count):
            key, offset = struct.unpack_from('<II', data, 8+at*8)
            if not table_end+8 <= offset < end:
                raise ValueError('GXT2 offset outside text section')
            stop = data.find(b'\0', offset, min(end, offset+MAX_TEXT*4+1))
            if stop < 0:
                raise ValueError('Unterminated GXT2 string')
            rows.append((f'0x{key:08X}', data[offset:stop].decode('utf-8', errors='strict')))
    else:
        if encoding=='utf-8-or-cp1252':
            try:text=data.decode('utf-8-sig',errors='strict')
            except UnicodeDecodeError:text=data.decode('cp1252',errors='strict')
        else:text = data.decode(encoding, errors='strict')
        for n, line in enumerate(text.splitlines(), 1):
            if not line.strip() or line.lstrip().startswith(('#', '//')):
                continue
            match = re.fullmatch(r'\s*(0x[0-9A-Fa-f]{1,8}|[A-Za-z0-9_]{1,128})\s*=\s?(.*)', line)
            if match:
                rows.append(match.groups())
            else:
                failures.append(n)
    if len(rows) > 500000:
        raise ValueError('Too many records in one input')
    return rows, failures


def visual_line(text):
    """Explicit presentation-visual adapter, preserving LTR islands.

    Only used on records containing Arabic presentation forms, after the caller
    explicitly selects this producer convention. This producer places vowel marks
    BEFORE the visual base, so they change order with it, not with punctuation to
    their left. Lam-alef expands AFTER ordering.
    It is not a general inverse of the Unicode bidi algorithm.
    """
    text=unicodedata.normalize('NFC',text)
    latin=r'A-Za-z0-9\u00c0-\u024f\u1e00-\u1eff'
    pattern = rf'~[^~]+~|[+\-]?[{latin}][{latin}_\x27’.,:/%+\-]*(?: [{latin}][{latin}_\x27’.,:/%+\-]*)*'
    units, at = [], 0
    for match in re.finditer(pattern, text):
        units.extend(text[at:match.start()])
        units.append(match.group()); at = match.end()
    units.extend(text[at:])
    mirrors = str.maketrans('()[]{}<>', ')(][}{><')
    return unicodedata.normalize('NFKC', ''.join(u.translate(mirrors) if len(u)==1 else u for u in reversed(units)))


def prepare(text, arabic=False, order='auto'):
    flags = []
    if '\x00' in text or any(ord(c)<32 and c not in '\t\r\n' for c in text) or len(text)>MAX_TEXT:
        flags.append('invalid_text')
    tokens = CONTROL.findall(text)
    unsupported = [t for t in tokens if t not in ['~z~','~n~'] and not re.fullmatch(r'~sl:(?:[0-9.]+:[0-9.]+)?~',t)]
    if unsupported or re.search(r'\{[^}]+\}|%[0-9.$]*[sdfiu]|<[^>]+>',text):
        flags.append('unresolved_markup_or_placeholder')
    # Timing boundaries and hard breaks keep visual conversion within each segment.
    segments = re.split(r'~n~|\r?\n|~sl:(?:[0-9.]+:[0-9.]+)?~', text.replace('~z~',''))
    converted = []
    has_forms = any(0xfb50<=ord(c)<=0xfdff or 0xfe70<=ord(c)<=0xfeff for c in text)
    for segment in segments:
        forms = any(0xfb50<=ord(c)<=0xfdff or 0xfe70<=ord(c)<=0xfefc for c in segment)
        if arabic and forms and order=='presentation-visual':
            # Mixed legal/markup paragraphs are not safe inversions of arbitrary bidi.
            if len(re.findall(r'[A-Za-z][A-Za-z ]{2,}', CONTROL.sub('',segment))) > 3:
                flags.append('complex_visual_order')
            converted.append(visual_line(segment))
        else:
            if arabic and forms and order=='auto': flags.append('arabic_order_unconfirmed')
            converted.append(unicodedata.normalize('NFKC',segment))
    value = '\n'.join(s.strip() for s in converted if s.strip()).translate(FORMAT_CONTROLS)
    if not value.strip(): flags.append('empty')
    if arabic and not re.search('[\u0600-\u06ff]',value): flags.append('no_arabic')
    if has_forms and arabic: flags.append('presentation_forms_converted')
    blocking = set(flags)-{'presentation_forms_converted'}
    return value, sorted(set(flags)), not blocking


def extract(installer, output):
    """Read CLR manifest resources with dnfile; no CLR loading or installation."""
    path = Path(installer)
    if path.stat().st_size > 128*1024*1024: raise ValueError('Installer too large')
    with path.open('rb') as stream:
        if stream.read(2) != b'MZ':raise ValueError('Unsupported installer: missing PE header')
    import dnfile
    pe = dnfile.dnPE(str(path))
    if not pe.net: raise ValueError('Unsupported installer: expected .NET resources')
    resources = {str(r.name):r.data for r in pe.net.resources if str(r.name) in ['r_text.gxt2.gz','r_install.xml','game.ini']}
    if not isinstance(resources.get('r_text.gxt2.gz'),bytes): raise ValueError('Supported text resource missing')
    out = Path(output); out.mkdir(parents=True,exist_ok=True)
    with gzip.GzipFile(fileobj=io.BytesIO(resources['r_text.gxt2.gz'])) as stream:
        table = stream.read(64*1024*1024+1)
    if len(table)>64*1024*1024: raise ValueError('Text resource exceeds expansion limit')
    rows, failures = parse_bytes_for_check(table)
    (out/'r_text.gxt2').write_bytes(table)
    report = {'installer_sha256':digest(path.read_bytes()),'installer_bytes':path.stat().st_size,'method':'Static dnfile CLR resource read + bounded gzip; no code executed','format':'CLR manifest resource / gzip / UTF-8 text export','extracted_bytes':len(table),'extracted_sha256':digest(table),'records':len(rows),'parse_failures':failures,'resources':{k:{'bytes':len(v),'sha256':digest(v)} for k,v in resources.items() if isinstance(v,bytes)}}
    (out/'extraction-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return report


def parse_bytes_for_check(data):
    # Do not write unvalidated embedded paths or inspect/execute other resources.
    data.decode('utf-8-sig',errors='strict')
    rows=[]; failures=[]
    for at,line in enumerate(data.decode('utf-8-sig').splitlines(),1):
        if not line.strip() or line.startswith('#'):continue
        m=re.fullmatch(r'\s*(0x[0-9a-fA-F]{1,8}|[A-Za-z0-9_]{1,128})\s*=\s?(.*)',line)
        if m:rows.append(m.groups())
        else:failures.append(at)
    return rows,failures


def build(args):
    if not re.fullmatch(r'[a-z0-9][a-z0-9._-]{0,63}',args.game_id) or not 0<len(args.title)<=100 or not 0<len(args.pack_version)<=32 or len(args.attribution)>4096 or len(args.permission)>2000 or len(args.timestamp)>64:
        raise ValueError('Invalid package metadata')
    output=Path(args.output);output.parent.mkdir(parents=True,exist_ok=True)
    english=collections.defaultdict(dict);english_rows=0;failures={};input_hashes={}
    root=Path(args.english)
    files=sorted(root.rglob('*.txt')) if root.is_dir() else [root]
    for file in files:
        rows,bad=parse_file(file,args.english_encoding)
        if bad:failures[file.relative_to(root).as_posix() if root.is_dir() else file.name]=bad
        input_hashes[file.relative_to(root).as_posix() if root.is_dir() else file.name]=digest(file.read_bytes())
        for key,text in rows:
            english_rows+=1;canonical=identifier(key)
            english[canonical].setdefault(text,[]).append(file.relative_to(root).as_posix() if root.is_dir() else file.name)
    arabic,bad=parse_file(args.arabic)
    ar_counts=collections.Counter(identifier(k) for k,_ in arabic)
    ar_variants=collections.defaultdict(set)
    for key,text in arabic:ar_variants[identifier(key)].add(text)
    report={'english_records':english_rows,'english_unique_ids':len(english),'arabic_records':len(arabic),'arabic_unique_ids':len(ar_counts),'english_conflicting_ids':sum(len(v)>1 for v in english.values()),'arabic_duplicate_id_records':sum(n-1 for n in ar_counts.values()),'arabic_conflicting_ids':sum(len(v)>1 for v in ar_variants.values()),'english_encoding_policy':args.english_encoding,'english_parse_failures':failures,'arabic_parse_failure_lines':bad,'english_file_sha256':input_hashes,'arabic_sha256':digest(Path(args.arabic).read_bytes()),'arabic_order':args.arabic_order,'english_revision':args.english_revision,'attribution':args.attribution,'permission':args.permission,'source_authorship':'Provided localization; translation method and human authorship not independently verified','matched_identifiers':len(set(english)&set(ar_counts)),'unmatched_arabic_identifiers':len(set(ar_counts)-set(english)),'unmatched_english_identifiers':len(set(english)-set(ar_counts))}
    dbpath=output.with_suffix('.sqlite-stage')
    if dbpath.exists():raise ValueError('Staging database already exists')
    db=sqlite3.connect(dbpath)
    by_source=collections.defaultdict(set);flags_count=collections.Counter();categories=collections.Counter();count=usable=0
    try:
        db.execute('PRAGMA page_size=4096');db.execute(SCHEMA)
        for key,raw_target in arabic:
            ident=identifier(key)
            candidates=english.get(ident,{})
            if len(candidates)!=1:continue
            raw_source=next(iter(candidates))
            source,source_flags,source_ok=prepare(raw_source)
            target,flags,target_ok=prepare(raw_target,True,args.arabic_order)
            flags=sorted(set(flags+source_flags))
            category='dialogue' if '~z~' in raw_source else 'general'
            provenance=';'.join(candidates[raw_source])
            if len(source)>4096 or len(target)>MAX_TEXT or len(provenance)>8192 or '\0' in source or '\0' in target:
                flags_count['excluded_invalid_or_oversized_record']+=1;continue
            ok=source_ok and target_ok and bool(normalize(source)) and len(source)<=4096
            if len(target)>MAX_TEXT:ok=False
            db.execute('INSERT INTO entries VALUES (?,?,?,?,?,?,?,?,?)',(ident,key,source,normalize(source),target,category,provenance,json.dumps(flags),int(ok)))
            count+=1;usable+=int(ok);categories[category]+=int(ok);flags_count.update(flags)
            if ok:by_source[normalize(source)].add(target)
        for sql in INDEXES.values():db.execute(sql)
        db.execute('PRAGMA user_version=1');db.commit()
        assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
        index_bytes=db.execute("SELECT coalesce(sum(pgsize),0) FROM dbstat WHERE name IN ('by_exact','by_normalized','by_identifier')").fetchone()[0]
        db.close()
        data=dbpath.read_bytes()
        if not 0<count<=500000 or len(data)>256*1024*1024:raise ValueError('Package outside import limits')
        manifest={'format_version':1,'schema_version':1,'game_id':args.game_id,'game_title':args.title,'source_language':'en','target_language':'ar','pack_version':args.pack_version,'record_count':count,'usable_count':usable,'categories':sorted(categories),'attribution':args.attribution,'permission':args.permission,'built_at':args.timestamp,'arabic_order':'logical','database_sha256':digest(data),'speaker_names':[],'coverage':'partial'}
        raw_manifest=(json.dumps(manifest,ensure_ascii=False,sort_keys=True,separators=(',',':'))+'\n').encode()
        checksums=json.dumps({'manifest.json':digest(raw_manifest),'translations.sqlite':digest(data)},sort_keys=True).encode()
        temporary=output.with_suffix('.glpack-stage')
        with zipfile.ZipFile(temporary,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
            for name,content in [('manifest.json',raw_manifest),('translations.sqlite',data),('checksums.json',checksums)]:
                info=zipfile.ZipInfo(name,date_time=(2020,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;z.writestr(info,content)
        temporary.replace(output)
        report.update(package_records=count,usable_records=usable,usable_percent_of_arabic=100*usable/max(1,len(arabic)),ambiguous_normalized_sources=sum(len(v)>1 for v in by_source.values()),flags=dict(flags_count),usable_categories=dict(categories),database_bytes=len(data),sqlite_index_bytes=index_bytes,pack_bytes=output.stat().st_size,pack_sha256=digest(output.read_bytes()),database_sha256=digest(data),validation='SQLite integrity_check passed; iPhone importer validation still required')
        Path(args.report).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        return report
    finally:
        db.close()
        if dbpath.exists():dbpath.unlink()


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    ex=sub.add_parser('extract');ex.add_argument('--installer',required=True);ex.add_argument('--output',required=True)
    b=sub.add_parser('build')
    for name in ['english','arabic','output','report','game-id','title','pack-version','attribution']:b.add_argument('--'+name,required=True)
    b.add_argument('--arabic-order',choices=['auto','logical','presentation-visual'],default='auto')
    b.add_argument('--english-revision',default='unspecified');b.add_argument('--permission',default='unknown; local generation only, do not redistribute without permission')
    b.add_argument('--english-encoding',choices=['utf-8-sig','utf-8-or-cp1252'],default='utf-8-sig')
    b.add_argument('--timestamp',default=datetime.datetime.now(datetime.timezone.utc).isoformat())
    args=p.parse_args()
    result=extract(args.installer,args.output) if args.command=='extract' else build(args)
    print(json.dumps({k:v for k,v in result.items() if k not in ['english_file_sha256','english_parse_failures']},ensure_ascii=False,indent=2))

if __name__=='__main__':main()
