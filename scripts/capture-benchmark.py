"""Read RGB frames to memory, report dimensions and time only."""
import statistics
import sys
import time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"desktop"))
from gamelingo.capture import DesktopCaptureSource
import mss

with mss.MSS() as cap:
    monitor=cap.monitors[1]
x,y,w,h=(monitor[k] for k in ("left","top","width","height"))
source=DesktopCaptureSource((x,y,x+w,y+h))
times=[]
for idx in range(24):
    start=time.perf_counter();frame=source.read();times.append(1000*(time.perf_counter()-start))
print("Physical Windows display:",frame.dimensions,"in-memory RGB frames:",len(times),
      "capture p50/p95 ms:",round(statistics.median(times),2), round(sorted(times)[22],2))

