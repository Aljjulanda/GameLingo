#!/usr/bin/env python3
"""Synthetic sentence-splitting research, never a production translator.

Uses an existing pinned Argos package without downloading or changing Windows
application files. Python CTranslate2/Windows timings do not certify iOS. The
native XCTest separately exercises GLTranslation with the same authored inputs.
"""
import argparse
import hashlib
import json
import pathlib
import statistics
import tempfile
import time
import zipfile

FIXTURES = [
    ['Mr. Morgan, wait.', 'Where are you going?'],
    ['Dr. Smith is here.', 'Let him in.'],
    ['We reached St. Denis.', 'What happens now?'],
    ['Mr. Morgan is here.'],
    ['Dr. Smith lives in St. Denis.'],
    ['"Wait... please."'],
]
DIGEST = 'e2a6e84337f7ebbb55f9dc61dcba3a861c0d786ae5a46fa198fd8d6473f5c775'
REQUIRED = ['model/model.bin', 'model/shared_vocabulary.txt', 'sentencepiece.model', 'metadata.json', 'README.md']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--repeats', type=int, default=3, choices=range(1, 11))
    args = parser.parse_args()
    import ctranslate2
    import sentencepiece

    if args.package.stat().st_size != 88_502_631:
        raise ValueError('Unexpected model package size')
    data = args.package.read_bytes()
    if hashlib.sha256(data).hexdigest() != DIGEST:
        raise ValueError('Unexpected model package hash')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='synthetic-argos-', dir=args.output.parent) as temporary:
        root = pathlib.Path(temporary)
        with zipfile.ZipFile(args.package) as archive:
            for name in REQUIRED:
                entry = archive.getinfo('en_ar/' + name)
                if entry.file_size > 250 * 1024 * 1024:
                    raise ValueError('Model entry exceeds its bound')
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(entry))
        metadata = json.loads((root / 'metadata.json').read_text(encoding='utf-8'))
        if metadata.get('from_code') != 'en' or metadata.get('to_code') != 'ar':
            raise ValueError('Unexpected language pair')
        tokenizer = sentencepiece.SentencePieceProcessor(model_file=str(root / 'sentencepiece.model'))
        engine = ctranslate2.Translator(str(root / 'model'), device='cpu', compute_type='int8', inter_threads=1, intra_threads=2)

        def run(text):
            pieces = tokenizer.encode(text, out_type=str)
            start = time.perf_counter()
            tokens = engine.translate_batch([pieces], beam_size=1, max_decoding_length=min(256, max(24, 2 * len(pieces) + 12)))[0].hypotheses[0]
            return tokenizer.decode(tokens), (time.perf_counter() - start) * 1000

        run('A synthetic warm up.')
        reports = []
        for parts in FIXTURES:
            source = ' '.join(parts)
            whole_runs = [run(source) for _ in range(args.repeats)]
            split_runs = []
            for index in range(args.repeats):
                segmented = [run(part) for part in parts] if len(parts) > 1 else [whole_runs[index]]
                split_runs.append((' '.join(item[0] for item in segmented), sum(item[1] for item in segmented)))
            if len({item[0] for item in whole_runs}) != 1 or len({item[0] for item in split_runs}) != 1:
                raise ValueError('Non-deterministic research output')
            reports.append(dict(source=source, whole=whole_runs[0][0], split=split_runs[0][0],
                                whole_median_ms=statistics.median(item[1] for item in whole_runs),
                                split_median_ms=statistics.median(item[1] for item in split_runs),
                                single_sentence=len(parts) == 1))
        result = dict(environment='Python CPU int8 research; NOT iOS or physical-device validation',
                      ctranslate2=ctranslate2.__version__, model_sha256=DIGEST,
                      repeats=args.repeats, fixtures=reports)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(dict(synthetic_fixtures=len(reports), output=str(args.output), repeats=args.repeats)))


if __name__ == '__main__':
    main()
