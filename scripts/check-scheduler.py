import json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"desktop"))
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from gamelingo.performance import Scheduler
s=Scheduler();checks=[]
for i in range(60):
    image=Image.fromarray(np.full((180,700),40+(i%30),dtype=np.uint8))
    ImageDraw.Draw(image).text((220,60),"Follow me to the gate.",font=ImageFont.truetype("arial.ttf",26),fill=245)
    checks.append(s.should_read(image,i*.1))
report={"fixture":"same bright subtitle, changing dark background over six seconds",
        "pixel_hash_changes":60,"smart_ocr_requests":sum(checks),"periodic_verification_seconds":.65}
Path(sys.argv[1]).write_text(json.dumps(report,indent=2))
print(report)

