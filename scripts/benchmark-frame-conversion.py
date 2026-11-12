import sys,time,json,statistics,gc
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'desktop'))
import numpy as np
from gamelingo.frame_conversion import owned_image
rng=np.random.default_rng(173);rows=[]
for w,h in [(1280,720),(1920,1080),(2560,1600)]:
 a=rng.integers(0,256,(h,w+8,4),dtype=np.uint8)[:,:w,:]
 samples={'old':[],'new':[]};cpu={'old':[],'new':[]}
 for i in range(64):
  for mode in (('old','new') if i%2 else ('new','old')):
   t=time.perf_counter();ct=time.process_time();im=owned_image(a,w,h,'RGB' if mode=='old' else 'L')
   # Same pre-existing consumer operation for both formats; no ROI settings change.
   out=im.crop((int(im.width*.16),int(im.height*.65),int(im.width*.84),int(im.height*.93))).convert('L')
   samples[mode].append((time.perf_counter()-t)*1000);cpu[mode].append((time.process_time()-ct)*1000)
 old=np.array(owned_image(a,w,h,'RGB').convert('L'));new=np.array(owned_image(a,w,h,'L'))
 delta=np.abs(old.astype(int)-new.astype(int))
 held=owned_image(a,w,h,'L');before=held.tobytes();a[:]=0;gc.collect();assert held.tobytes()==before
 rows.append({'input':[w,h],'pixel_max_difference':int(delta.max()),'timings':{k:{'cpu_mean_ms':sum(cpu[k][4:])/len(cpu[k][4:]),'median_ms':statistics.median(v[4:]),'p95_ms':float(np.percentile(v[4:],95))} for k,v in samples.items()}})
Path(sys.argv[1]).write_text(json.dumps(rows,indent=2));print(rows)
