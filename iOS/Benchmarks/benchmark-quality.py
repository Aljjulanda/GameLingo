#!/usr/bin/env python3
"""Actual Release/current Swift post-OCR equivalence and same-host timings.

Uses authored synthetic OCR observations and a synchronous stub translator.
Excludes Vision, SQLite lookup, Argos inference, asynchronous delivery, WSS and TV.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = 'bf3675e66147ba9202eec7252726e16b2c9090f6'
REL = 'iOS/GameLingo/Core/'


def old(path):
    return subprocess.check_output(['git', 'show', BASELINE + ':' + path], cwd=ROOT.parent)


def main():
    if subprocess.run(['git', 'cat-file', '-e', BASELINE + '^{commit}'], cwd=ROOT.parent, capture_output=True).returncode:
        subprocess.run(['git', 'fetch', '--depth=1', 'origin', BASELINE], cwd=ROOT.parent, check=True)
    records = {}
    with tempfile.TemporaryDirectory(prefix='gamelingo-quality-benchmark-') as temporary:
        work = Path(temporary)
        for variant in ['baseline', 'current']:
            folder = work / variant
            folder.mkdir()
            paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE, REL], cwd=ROOT.parent, text=True).splitlines() if variant == 'baseline' else [str(p.relative_to(ROOT.parent)).replace('\\', '/') for p in (ROOT / 'GameLingo/Core').glob('*.swift')]
            sources = []
            for path in paths:
                if not path.endswith('.swift'):
                    continue
                destination = folder / Path(path).name
                destination.write_bytes(old(path) if variant == 'baseline' else (ROOT.parent / path).read_bytes())
                sources.append(str(destination))
            if variant == 'baseline':
                # Extract the actual approved Vision fallback gate verbatim;
                # only the method's enclosing type/mutating annotation changes.
                vision = old('iOS/GameLingo/OCR/VisionDialogueOCR.swift').decode()
                gate = vision[vision.index('    func select('):vision.rfind('\n}')].replace('func select(', 'mutating func select(', 1)
                adapter = '''import Foundation
struct LegacySelection {
    private var previousSignature: [String] = []
GATE
}
func legacyResolve(_ lines: [OCRLine], selector: inout LegacySelection) -> BenchmarkReading {
    if let reading = StructuredDialogue.resolve(lines,roi:.dialogue,knownNames:"Arthur,John") {
        return BenchmarkReading(content:reading.content,box:reading.box,confidence:reading.confidence)
    }
    let selected = selector.select(lines,roi:.dialogue)
    let confidence = selected.map(\\.confidence).min() ?? 0
    let ordered = selected.sorted{$0.box.y < $1.box.y}
    let separate = ordered.count >= 2 && ordered[0].box.w < ordered[1].box.w*0.5 && ordered[0].box.h <= ordered[1].box.h*1.1
    guard !selected.isEmpty else { return BenchmarkReading(content:DialogueContent(text:"",speaker:nil),box:.dialogue,confidence:0) }
    let text = String(selected.map(\\.text).joined(separator:"\\n").prefix(1800))
    let x = selected.map(\\.box.x).min()!, y = selected.map(\\.box.y).min()!
    let right = selected.map{$0.box.x+$0.box.w}.max()!, bottom = selected.map{$0.box.y+$0.box.h}.max()!
    return BenchmarkReading(content:DialogueContent.parse(text,knownNames:"Arthur,John",separateLabel:separate,confidence:confidence),box:SourceBox(x:x,y:y,w:right-x,h:bottom-y),confidence:confidence)
}
'''.replace('GATE', gate)
                destination = folder / 'LegacyAdapter.swift'
                destination.write_text(adapter, encoding='utf-8')
                sources.append(str(destination))
            executable = folder / 'benchmark'
            command = ['swiftc', '-O', '-I', str(ROOT / 'CSQLite'), *sources, str(ROOT / 'Benchmarks/QualityPipelineMain.swift'), '-lsqlite3', '-o', str(executable)]
            if variant == 'current':
                command += ['-D', 'QUALITY_CURRENT']
            subprocess.run(command, check=True)
            records[variant + '_off'] = json.loads(subprocess.check_output([str(executable)], text=True))
            if variant == 'current':
                records['current_enabled'] = json.loads(subprocess.check_output([str(executable), 'enabled'], text=True))
        assert records['baseline_off']['fixture_streams'] == records['current_off']['fixture_streams'], 'Quality OFF differs from approved Release outputs'
    report = dict(environment='Same CI host, optimized actual Swift Core; synthetic OCR + synchronous stub; excludes Vision/SQLite/Argos/asynchronous worker/WSS/TV and physical hardware', baseline_sha=BASELINE, all_off_equivalent=True, fixture_streams=len(records['baseline_off']['fixture_streams']), results={})
    for variant, value in records.items():
        streams = value.pop('fixture_streams')
        value['canonical_sha256'] = hashlib.sha256(json.dumps(streams, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
        value['messages'] = sum(map(len, streams))
        report['results'][variant] = value
    output = ROOT / 'build/logs/quality-pipeline-benchmark.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('SYNTHETIC_QUALITY_PIPELINE ' + json.dumps(report))


if __name__ == '__main__':
    main()
