#!/usr/bin/env python3
"""Compare correct English first, then actual exported Vision OCR. Windows CPU
measurements do not establish iPhone speed, power, or an accepted replacement.
Use --ocr FILE for the JSON attachment exported by the isolated native test.
"""
import argparse
import gc
import hashlib
import json
from pathlib import Path
import statistics
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.build/model-python'))
import ctranslate2
import sentencepiece
import psutil
from sacrebleu.metrics import CHRF

def sha(file):
    with file.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--ocr',type=Path);args=parser.parse_args()
    cases=json.loads((ROOT/'Benchmarks/play-model-cases.json').read_text(encoding='utf-8'))
    if args.ocr:
        actual={x['id']:x for x in json.loads(args.ocr.read_text(encoding='utf-8'))}
        for case in list(cases):
            if case['id'] in actual:
                assert actual[case['id']]['correct_source']==case['source']
                cases.append({**case,'input_kind':'actual-Vision','source':actual[case['id']]['vision_ocr']})
    baseline=ROOT/'GameLingoTests/Fixtures/en_ar'
    candidate=ROOT/'.build/opus-comparison/opus-big-2022'
    original=candidate/'original'
    pin=json.loads((candidate/'acquisition.json').read_text())
    assert sha(candidate/'official.zip')==pin['sha256']=='e8733833b816f9ac5bc7c13b196b0683fc42ae392bddf26d6d574e179662a1e5'
    converted=candidate/'ctranslate2-int8'
    if not converted.exists():
        model=list(original.rglob('*.npz'));vocab=list(original.rglob('*.vocab.yml'))
        assert len(model)==len(vocab)==1
        ctranslate2.converters.MarianConverter(str(model[0]),[str(vocab[0]),str(vocab[0])]).convert(str(converted),quantization='int8')
    assert sha(converted/'model.bin') != sha(baseline/'model/model.bin'),'Different name is not a different model'
    outputs=[];summaries=[]
    for name,folder,source_sp,target_sp,prefix in [
        ('argos-en_ar-1.0',baseline/'model',baseline/'sentencepiece.model',baseline/'sentencepiece.model',[]),
        ('opus-tc-big-2022',converted,original/'source.spm',original/'target.spm',['>>ara<<'])]:
        tokenizer=sentencepiece.SentencePieceProcessor(model_file=str(source_sp));detokenizer=sentencepiece.SentencePieceProcessor(model_file=str(target_sp))
        load=time.perf_counter();engine=ctranslate2.Translator(str(folder),device='cpu',compute_type='int8',intra_threads=2);load=time.perf_counter()-load
        timings=[];peak=psutil.Process().memory_info().rss;records=[]
        for case in cases:
            pieces=prefix+tokenizer.encode(case['source'],out_type=str)
            for repeat in range(3):
                start=time.perf_counter();result=engine.translate_batch([pieces],beam_size=1,max_decoding_length=min(256,max(24,2*len(pieces)+12)))
                translation=detokenizer.decode([p for p in result[0].hypotheses[0] if p not in ('</s>','<s>','>>ara<<')])
                elapsed=(time.perf_counter()-start)*1000;timings.append(elapsed);peak=max(peak,psutil.Process().memory_info().rss)
            record={**case,'input_kind':case.get('input_kind','correct-source'),'model':name,'translation':translation,'milliseconds_last':elapsed}
            records.append(record)
        summaries.append(dict(model=name,load_seconds=load,median_ms=statistics.median(timings),p95_ms=sorted(timings)[int(.95*(len(timings)-1))],sampled_process_rss_bytes=peak,model_sha256=sha(folder/'model.bin'),model_bytes=(folder/'model.bin').stat().st_size,
            chrf_by_split={split:CHRF().corpus_score([r['translation'] for r in records if r['split']==split and r['input_kind']=='correct-source'],[[r['reference'] for r in records if r['split']==split and r['input_kind']=='correct-source']]).score for split in ['development','heldout']}))
        outputs.extend(records);del engine;gc.collect()
    report=dict(platform='Windows x64 CPU, int8, 2 threads, beam 1, 3 repetitions; not iPhone validation',source_corpus_sha256=sha(ROOT/'Benchmarks/play-model-cases.json'),actual_ocr=args.ocr is not None,summaries=summaries,outputs=outputs,
        decision='Research only. No alternative approved or packaged. chrF and this small authored corpus alone are not proof of semantic quality or acceptable iPhone speed.')
    target=ROOT/'.build/opus-comparison'/('results-with-vision.json' if args.ocr else 'results-correct-source.json')
    target.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'report':str(target),'summaries':summaries,'actual_ocr':report['actual_ocr']},indent=2))

if __name__=='__main__':main()
