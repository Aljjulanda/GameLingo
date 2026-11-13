#!/usr/bin/env python3
"""Windows CPU experiment, never an iPhone benchmark or an application engine.
Run after preparing verified Qwen GGUF/llama-server under .build/context-benchmark
and Scripts/fetch-test-model.py. No game/user dialogue is collected.
"""
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time
import urllib.error
import urllib.request

import ctranslate2
import sentencepiece
import psutil

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build/context-benchmark'
MODEL_SHA = '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db'
assert hashlib.sha256((BUILD / 'qwen.gguf').read_bytes()).hexdigest() == MODEL_SHA
CASES = [
    ('bank', 'Wait near the bank.', 'انتظر بالقرب من ضفة النهر.'),
    ('negation', 'We will not go to the camp.', 'لن نذهب إلى المعسكر.'),
    ('number', 'Collect 11 coins before leaving.', 'اجمع 11 قطعة نقدية قبل المغادرة.'),
    ('idiom', "It is raining cats and dogs.", 'إنها تمطر بغزارة.'),
]
HISTORY = ['We crossed the river.','The water is deep.','Our camp is beyond the bridge.',
           'We are looking for shelter.','The river bank is the meeting place.'] * 4


def api(path, data=None):
    req = urllib.request.Request('http://127.0.0.1:39998'+path,
        data=None if data is None else json.dumps(data).encode(),
        headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=90) as response: return json.load(response)


records = []
fixture = ROOT / 'GameLingoTests/Fixtures/en_ar'
start = time.perf_counter()
tokenizer = sentencepiece.SentencePieceProcessor(model_file=str(fixture / 'sentencepiece.model'))
argos = ctranslate2.Translator(str(fixture / 'model'),device='cpu',compute_type='int8',intra_threads=2)
argos_load = time.perf_counter()-start
for kind, source, reference in CASES:
    start = time.perf_counter(); pieces = tokenizer.encode(source,out_type=str)
    result = argos.translate_batch([pieces],beam_size=1,max_decoding_length=min(256,max(24,2*len(pieces)+12)))
    output = tokenizer.decode(result[0].hypotheses[0])
    records.append(dict(engine='Argos-CTranslate2',capacity=0,case=kind,source=source,reference=reference,
        translation=output,milliseconds=(time.perf_counter()-start)*1000,rss_bytes=psutil.Process().memory_info().rss))
del argos

start = time.perf_counter()
with (BUILD / 'llama-server.log').open('wb') as log:
    child = subprocess.Popen([str(BUILD/'llama/llama-server.exe'),'-m',str(BUILD/'qwen.gguf'),
        '--host','127.0.0.1','--port','39998','-t','2','-tb','2','-c','2048','-ngl','0','--parallel','1','--log-disable'],
        stdout=log,stderr=log,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    try:
        ready = False
        for _ in range(90):
            if child.poll() is not None: raise RuntimeError('Benchmark server exited; inspect local log')
            try: api('/health'); ready=True; break
            except (urllib.error.URLError,TimeoutError): time.sleep(1)
        assert ready, 'Benchmark server did not become ready'
        qwen_load = time.perf_counter()-start
        for capacity in [1,5,10,20]:
            for kind, source, reference in CASES:
                memory = '\n'.join(HISTORY[-capacity:])
                prompt = f'Context (do not translate or repeat):\n{memory}\n\nNEW dialogue: {source}'
                start = time.perf_counter()
                response = api('/v1/chat/completions',{'model':'local','temperature':0,'max_tokens':96,
                    'messages':[{'role':'system','content':'Translate only the NEW English dialogue into natural Arabic. Use context to resolve meaning. Preserve negation and numbers. Output Arabic translation only.'},
                                {'role':'user','content':prompt}]})
                output = response['choices'][0]['message']['content']
                record = dict(engine='Qwen2.5-0.5B-Q4_K_M-CPU',capacity=capacity,case=kind,source=source,reference=reference,
                    translation=output,milliseconds=(time.perf_counter()-start)*1000,rss_bytes=psutil.Process(child.pid).memory_info().rss)
                records.append(record)
                print(f"Qwen context={capacity} case={kind} milliseconds={record['milliseconds']:.0f}",flush=True)
    finally:
        child.terminate()
        try: child.wait(timeout=10)
        except subprocess.TimeoutExpired: child.kill(); child.wait()

report = dict(environment='Windows x64 CPU, two inference threads; NOT iPhone hardware',
    argos_runtime=ctranslate2.__version__,qwen_revision='9217f5db79a29953eb74d5343926648285ec7e67',
    qwen_sha256=MODEL_SHA,llama_release='b12367',
    argos_load_seconds=argos_load,qwen_load_seconds=qwen_load,results=records)
(BUILD/'results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
for engine in sorted(set(r['engine'] for r in records)):
    rows=[r for r in records if r['engine']==engine]
    print(engine,'median_ms=',round(statistics.median(r['milliseconds'] for r in rows)),
        'max_rss_mb=',round(max(r['rss_bytes'] for r in rows)/1048576))
