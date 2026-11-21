#!/usr/bin/env python3
"""Free, official Marian assets for offline comparison only; never IPA assets.
Initial acquisition records SHA-256; later comparison requires those exact files.
The publisher must never ship an unaccepted candidate merely because it converts.
"""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.build/model-python'))
import ctranslate2

ASSETS = {
    'opus-big-2022': ('https://object.pouta.csc.fi/Tatoeba-MT-models/eng-ara/opusTCv20210807+bt_transformer-big_2022-02-25.zip','CC-BY-4.0','https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-en-ar'),
}
BUILD = ROOT/'.build/opus-comparison'
BUILD.mkdir(parents=True,exist_ok=True)

def prepare(item):
    name,(url,license,card) = item
    folder=BUILD/name;folder.mkdir(exist_ok=True)
    archive=folder/'official.zip'
    if not archive.exists():
        part=folder/'official.partial'
        with urllib.request.urlopen(url,timeout=60) as response,part.open('wb') as output:
            total=0
            while block:=response.read(1024*1024):
                total+=len(block)
                if total>3_000_000_000:raise ValueError('Candidate exceeds safety limit')
                output.write(block)
        part.replace(archive)
    with archive.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    manifest=dict(id=name,url=url,model_card=card,license=license,sha256=digest,bytes=archive.stat().st_size,runtime=ctranslate2.__version__)
    pin=folder/'acquisition.json'
    if pin.exists():assert json.loads(pin.read_text())==manifest,'Asset changed since acquisition'
    pin.write_text(json.dumps(manifest,indent=2))
    with zipfile.ZipFile(archive) as bundle:
        for entry in bundle.infolist():
            if entry.is_dir():continue
            # Extract model/tokenizer/config text only, never executables or shell scripts.
            suffix=Path(entry.filename).suffix
            if suffix not in ('.npz','.yml','.json','.spm','.model','.txt','.md'):continue
            target=(folder/'original'/entry.filename).resolve()
            assert target.is_relative_to((folder/'original').resolve()) and entry.file_size<=2_500_000_000
            target.parent.mkdir(parents=True,exist_ok=True)
            if not target.exists():
                with bundle.open(entry) as src,target.open('wb') as dst:
                    import shutil
                    shutil.copyfileobj(src,dst)
    print(json.dumps(manifest),flush=True)
    return manifest

if __name__=='__main__':
    with ThreadPoolExecutor(max_workers=2) as pool:
        acquired=list(pool.map(prepare,ASSETS.items()))
    (BUILD/'acquired.json').write_text(json.dumps(acquired,indent=2))
