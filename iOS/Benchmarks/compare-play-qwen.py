#!/usr/bin/env python3
"""Second free candidate, separate weights AND runtime. Fixed prompt and heldout
split; no paid endpoint, gameplay capture, tuning on heldout, or iOS claim.
"""
import argparse,hashlib,json,statistics,subprocess,sys,time,urllib.error,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.build/model-python'))
import psutil
from sacrebleu.metrics import CHRF
parser=argparse.ArgumentParser();parser.add_argument('--ocr',type=Path);args=parser.parse_args()
build=ROOT/'.build/context-benchmark'
with (build/'qwen.gguf').open('rb') as stream:assert hashlib.file_digest(stream,'sha256').hexdigest()=='74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db'
cases=json.loads((ROOT/'Benchmarks/play-model-cases.json').read_text(encoding='utf-8'))
if args.ocr:
    actual={x['id']:x for x in json.loads(args.ocr.read_text(encoding='utf-8'))}
    for case in list(cases):
        if case['id'] in actual:cases.append({**case,'input_kind':'actual-Vision','source':actual[case['id']]['vision_ocr']})
def api(path,data=None):
    request=urllib.request.Request('http://127.0.0.1:39998'+path,data=None if data is None else json.dumps(data).encode(),headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(request,timeout=60) as response:return json.load(response)
with (build/'play-qwen.log').open('wb') as log:
    start=time.perf_counter()
    child=subprocess.Popen([str(build/'llama/llama-server.exe'),'-m',str(build/'qwen.gguf'),'--host','127.0.0.1','--port','39998','-t','2','-tb','2','-c','2048','-ngl','0','--parallel','1','--log-disable'],stdout=log,stderr=log,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    try:
        for _ in range(45):
            assert child.poll() is None
            try:api('/health');break
            except (urllib.error.URLError,TimeoutError):time.sleep(1)
        load=time.perf_counter()-start;outputs=[];timings=[];rss=0
        for case in cases:
            start=time.perf_counter();response=api('/v1/chat/completions',{'model':'local','temperature':0,'max_tokens':96,'messages':[{'role':'system','content':'Translate the English game text into Arabic. Preserve negation, pronouns, names and numbers. Output only the translation.'},{'role':'user','content':case['source']}]})
            elapsed=(time.perf_counter()-start)*1000;timings.append(elapsed);rss=max(rss,psutil.Process(child.pid).memory_info().rss)
            outputs.append({**case,'input_kind':case.get('input_kind','correct-source'),'translation':response['choices'][0]['message']['content'],'milliseconds':elapsed})
    finally:
        child.terminate()
        try:child.wait(timeout=10)
        except subprocess.TimeoutExpired:child.kill();child.wait()
report=dict(model='Qwen2.5-0.5B-Instruct Q4_K_M',license='Apache-2.0',runtime='llama.cpp b12367, Windows x64 CPU, 2 threads',repetitions=1,actual_ocr=args.ocr is not None,load_seconds=load,median_ms=statistics.median(timings),p95_ms=sorted(timings)[int(.95*(len(timings)-1))],sampled_server_rss_bytes=rss,
    chrf_by_split={split:CHRF().corpus_score([r['translation'] for r in outputs if r['split']==split and r['input_kind']=='correct-source'],[[r['reference'] for r in outputs if r['split']==split and r['input_kind']=='correct-source']]).score for split in ['development','heldout']},outputs=outputs,decision='Research only, not approved or packaged. Different runtime and arrangement from CTranslate2; not an iPhone speed comparison.')
target=ROOT/'.build/opus-comparison'/('qwen-with-vision.json' if args.ocr else 'qwen-correct-source.json');target.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='outputs'},indent=2))
