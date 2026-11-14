#!/usr/bin/env python3
"""Transient real-data validation. Never publishes localization or runs installer.

All downloaded/extracted data stays under ignored .build/rdr2-ci-private. Only
content-free counts/timing are emitted to Actions logs and validation artifacts.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import urllib.request
import zipfile

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'iOS/.build/rdr2-ci-private'
REV='cdb2b8ab3134291a19a86d8d35fe0bd48cb8f926'
INSTALLER_HASH='3eaead8f4e851ad6c6c9a894415799e047928c522f009a632830cc3826fd0598'
MAIN=r'''
import Foundation
@main struct Validation {
    static func main() throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        let manifest = try PackManifest.decode(Data(contentsOf:root.appendingPathComponent("manifest.json")))
        let start = ProcessInfo.processInfo.systemUptime
        let database = try PackDatabase(url:root.appendingPathComponent("translations.sqlite"))
        try database.validateContents(manifest:manifest)
        let validationMS = (ProcessInfo.processInfo.systemUptime-start)*1000
        let inputs = try JSONDecoder().decode([[String:String]].self,from:Data(contentsOf:root.appendingPathComponent("samples.json")))
        var timing: [Double] = [], accepted = 0, rejected = 0
        for sample in inputs {
            let before = ProcessInfo.processInfo.systemUptime
            let result = try database.lookup(sample["source"]!,category:sample["category"]!)
            timing.append((ProcessInfo.processInfo.systemUptime-before)*1000)
            if sample["expect"] == "match" {
                guard result.text == sample["target"] else { throw PackFailure.invalid }; accepted += 1
            } else {
                guard result.text == nil else { throw PackFailure.invalid }; rejected += 1
            }
        }
        timing.sort()
        let result: [String:Any] = ["native_validation_ms":validationMS,"records":manifest.recordCount,"eligible_rows":manifest.usableCount,"verified_matches":accepted,"verified_rejections":rejected,"lookup_samples":timing.count,"lookup_average_ms":timing.reduce(0,+)/Double(max(1,timing.count)),"lookup_p95_ms":timing[max(0,Int(ceil(Double(timing.count)*0.95))-1)],"environment":"Actual real RDR2 database, native SQLite and Swift on CI Mac; not physical iPhone or gameplay; correctness is expected lookup decision, not a human linguistic certification"]
        print("REAL_RDR2_NATIVE_VALIDATION "+String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self))
    }
}
'''

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--python-only',action='store_true');args=parser.parse_args()
    WORK.mkdir(parents=True,exist_ok=True)
    packages=ROOT/'iOS/.build/pack-python'
    subprocess.run([sys.executable,'-m','pip','install','--disable-pip-version-check','--target',str(packages),'-r',str(Path(__file__).with_name('requirements-extraction.txt'))],check=True,stdout=subprocess.DEVNULL)
    sys.path.insert(0,str(packages));sys.path.insert(0,str(Path(__file__).parent))
    import convert as c
    installer=WORK/'Arabic-RDR2.exe'
    if not installer.exists():
        with urllib.request.urlopen('https://arabic-pc.github.io/downloads/Arabic-RDR2.exe',timeout=60) as response:
            data=response.read(128*1024*1024+1)
        if len(data)>128*1024*1024:raise ValueError('Installer download exceeds bound')
        installer.write_bytes(data)
    assert c.digest(installer.read_bytes())==INSTALLER_HASH,'Upstream installer changed; review required'
    english=WORK/'english'
    if not english.exists():subprocess.run(['git','clone','--quiet','https://github.com/cedricalpatch/Red-Dead-Redemption-2-Text-Files.git',str(english)],check=True)
    subprocess.run(['git','-C',str(english),'checkout','--quiet',REV],check=True)
    assert subprocess.check_output(['git','-C',str(english),'rev-parse','HEAD'],text=True).strip()==REV
    extraction=c.extract(installer,WORK)
    options=argparse.Namespace(english=str(english),arabic=str(WORK/'r_text.gxt2'),output=str(WORK/'RDR2-Arabic.glpack'),report=str(WORK/'private-conversion-report.json'),game_id='rdr2',title='Red Dead Redemption 2',pack_version='1.5-gl1',attribution='Arabic PC supplied installer 1.5; English cedricalpatch '+REV,permission='Unknown redistribution permission; local generation only; authorship unverified',timestamp='2026-11-14T00:00:00Z',english_revision=REV,english_encoding='utf-8-or-cp1252',arabic_order='presentation-visual')
    report=c.build(options)
    with zipfile.ZipFile(options.output) as archive:
        for name in ['manifest.json','translations.sqlite']:(WORK/name).write_bytes(archive.read(name))
    connection=sqlite3.connect(WORK/'translations.sqlite')
    samples=[]
    try:
        # Explicit expected unique/ambiguous decisions from the actual indexed data.
        for category in ['dialogue','general']:
            rows=connection.execute("SELECT source,min(target),count(*),count(distinct target),min(usable) FROM entries WHERE category=? GROUP BY source HAVING count(distinct target)=1 AND min(usable)=1 AND count(*)<=32 ORDER BY source LIMIT 500",(category,)).fetchall()
            for source,target,*_ in rows:
                candidates=connection.execute("SELECT target,usable FROM entries WHERE source=? AND category IN (?, 'general') LIMIT 33",(source,category)).fetchall()
                accepted=len(candidates)<=32 and all(r[1] for r in candidates) and len({r[0] for r in candidates})==1
                samples.append(dict(source=source,target=target,category=category,expect='match' if accepted else 'reject'))
        ambiguous=connection.execute("SELECT source,category FROM entries GROUP BY source,category HAVING count(distinct target)>1 ORDER BY source LIMIT 100").fetchall()
        samples += [dict(source=s,category=category,expect='reject') for s,category in ambiguous]
        for source in ['Synthetic missing line, not present in this localization.','We will collect -991122 coins near the synthetic gate.']:
            assert connection.execute('SELECT 1 FROM entries WHERE normalized=? LIMIT 1',(c.normalize(source),)).fetchone() is None
            samples.append(dict(source=source,category='dialogue',expect='reject'))
    finally:connection.close()
    (WORK/'samples.json').write_text(json.dumps(samples,ensure_ascii=False),encoding='utf-8')
    safe={k:v for k,v in report.items() if k not in ['english_file_sha256','english_parse_failures','attribution','permission']}
    safe['extraction']={k:v for k,v in extraction.items() if k!='resources'}
    safe['source_data_published']=False
    if not args.python_only:
        harness=WORK/'Main.swift';harness.write_text(MAIN,encoding='utf-8');binary=WORK/'native-validation'
        subprocess.run(['swiftc','-O',str(ROOT/'iOS/GameLingo/Core/PackDatabase.swift'),str(ROOT/'iOS/GameLingo/Core/Dialogue.swift'),str(ROOT/'iOS/GameLingo/Core/SubtitlePresentation.swift'),str(harness),'-lsqlite3','-o',str(binary)],check=True)
        output=subprocess.check_output([str(binary),str(WORK)],text=True);print(output.strip())
        safe['native']=json.loads(output.split('REAL_RDR2_NATIVE_VALIDATION ',1)[1])
    target=ROOT/'iOS/build/logs/translation-pack-validation.json';target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(safe,indent=2)+'\n',encoding='utf-8')
    print('REAL_RDR2_COUNTS '+json.dumps({k:safe[k] for k in ['english_records','arabic_records','matched_identifiers','package_records','usable_records','ambiguous_normalized_sources']}))

if __name__=='__main__':main()
