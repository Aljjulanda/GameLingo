#!/usr/bin/env python3
"""Compile the actual old/new portable tracker on the same CI Mac; no phone claims."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
COMMON=['Dialogue.swift','DialogueContent.swift']
MAIN=r'''
import Foundation
@main struct Benchmark {
    static func main() {
        var tracker=DialogueTracker()
        let start=ProcessInfo.processInfo.systemUptime
        var emitted=0
        for i in 0..<10000 {
            let now=Double(i)*0.35
            let phase=i%40
            let text=phase==8 || phase==9 ? "" : phase==20 ? "What happened?" : "We need to leave now."
            if case .dialogue = tracker.observe(text:text,box:.dialogue,now:now,frameMilliseconds:Int64(i)*350,speaker:phase==20 ? "John" : "Arthur") {emitted+=1}
        }
        let ms=(ProcessInfo.processInfo.systemUptime-start)*1000
        print("{\"observations\":10000,\"emitted_jobs\":\(emitted),\"milliseconds\":\(ms)}")
    }
}
'''
records={}
with tempfile.TemporaryDirectory(prefix='gamelingo-core-benchmark-') as temp:
    work=Path(temp)
    for variant in ['baseline_0.2.0','development_0.2.1']:
        folder=work/variant;folder.mkdir()
        sources=[]
        names=COMMON if variant.startswith('baseline') else COMMON+['SubtitlePresentation.swift']
        for name in names:
            if variant.startswith('baseline'):
                data=subprocess.check_output(['git','show',f'stable/real-device-0.2.0:iOS/GameLingo/Core/{name}'])
            else:data=(ROOT/'GameLingo/Core'/name).read_bytes()
            path=folder/name;path.write_bytes(data);sources.append(str(path))
        main=folder/'Main.swift';main.write_text(MAIN,encoding='utf-8');sources.append(str(main))
        executable=folder/'benchmark'
        subprocess.run(['swiftc','-O',*sources,'-o',str(executable)],check=True)
        samples=[json.loads(subprocess.check_output([str(executable)],text=True)) for _ in range(3)]
        records[variant]=samples
report={'environment':'Same CI macOS host, optimized portable Swift tracker only; NOT OCR, model, phone CPU, battery or thermal benchmark',
        'workload':'10,000 observations; 2 short blank OCR readings per 40 observations and intervening dialogue; three repetitions',
        'baseline_tag':'stable/real-device-0.2.0','results':records}
out=ROOT/'build/logs/maintenance-benchmark.json';out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('SYNTHETIC_PORTABLE_MAINTENANCE '+json.dumps(report))
