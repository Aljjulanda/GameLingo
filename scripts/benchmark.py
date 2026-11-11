import asyncio
import json
import statistics as stats
import sys
import tempfile
import time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"desktop"))
from gamelingo.diagnostics import sample_image
from gamelingo.ocr import WindowsOCR
from gamelingo.translation import Memory,ArgosTranslationProvider
from gamelingo.storage import data_root
from gamelingo.capture import crop

cases=[
 ("Open the door.",42,"white"),("Find the hidden key.",34,"white"),
 ("Collect 12 coins.",32,"white"),("Press X to continue.",40,"#eeeeee"),
 ("Turn left at the gate.",20,"#a8b3b6"),("Save game",24,"white"),
 ("Return to the village.",32,"white"),("The door is locked.",30,"#bbc8c8"),
 ("Wait here.\nI will return.",29,"white"),("Meet Elena at dawn.",26,"white"),
 ("Inventory",44,"white"),("You have 25 arrows.",30,"white")]
def distribution(values):
    from math import ceil
    return {"count":len(values),"p50_ms":round(stats.median(values),2),"p95_ms":round(sorted(values)[ceil(.95*len(values))-1],2)}
async def main():
    ocr=WindowsOCR();model=ArgosTranslationProvider(data_root()/"models")
    rows=[];skips=[]
    with tempfile.TemporaryDirectory() as folder:
        memory=Memory(Path(folder)/"bench.sqlite")
        for line,size,color in cases:
            img=sample_image(line,size,color);start=time.perf_counter()
            region=crop(img,(.04,.62,.92,.35));p=time.perf_counter()
            read=await ocr.read(region);r=time.perf_counter()
            text=" ".join(item.text for item in read);out=memory.resolve(text,model,{});t=time.perf_counter()
            assert memory.resolve(text,model,{})==out;end=time.perf_counter()
            rows.append(dict(source=line,ocr=text,arabic=out,exact=text==" ".join(line.split()),prep_ms=(p-start)*1000,
                ocr_ms=(r-p)*1000,translation_ms=(t-r)*1000,cache_ms=(end-t)*1000,total_ms=(t-start)*1000))
        memory.close()
    output={"fixture":"12 original synthetic English text cards, Windows CPU. Model loaded before timing.",
            "ocr_exact":sum(r["exact"] for r in rows),"rows":rows,
            "summary":{k:distribution([r[k] for r in rows]) for k in ("prep_ms","ocr_ms","translation_ms","cache_ms","total_ms")}}
    Path(sys.argv[1]).write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding="utf-8")
    print("Exact",output["ocr_exact"],"/",len(rows),output["summary"])
asyncio.run(main())

