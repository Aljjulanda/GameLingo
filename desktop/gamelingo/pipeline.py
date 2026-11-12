import asyncio
import concurrent.futures
import hashlib
import threading
import time
from difflib import SequenceMatcher
from .capture import CaptureUnavailable, crop
from .ocr import WindowsOCR
from .tracking import Tracker, dialogue_block, still_visible_prefix
from .translation import Memory, ArgosTranslationProvider
from .network import envelope


class Pipeline:
    """One OCR worker and one translator. Only the newest outstanding line is retained."""
    def __init__(self, source, roi, rate, models, db, glossary, profile, notify, publish, font=25, subtitles_only=False):
        self.source, self.roi, self.rate = source, roi, rate
        self.models, self.db, self.glossary, self.profile = models, db, glossary, profile
        self.notify, self.publish, self.font = notify, publish, font
        self.stop_event = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.ocr_count=0
        self.started_at=time.monotonic()
        self.metrics={}
        self.scheduler=None
        self.subtitles_only = subtitles_only

    def _run(self):
        try:
            asyncio.run(self._loop())
        except Exception as err:
            self.notify("error", str(err))
        finally:
            if hasattr(self.source, "close"):
                self.source.close()
            self.publish(envelope("subtitle_clear"))
            self.notify("stopped", "")

    async def _loop(self):
        ocr, track = WindowsOCR("en"), Tracker()
        pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        def create():
            return ArgosTranslationProvider(self.models), Memory(self.db)
        try:
            engine, memory = pool.submit(create).result()
        except Exception:
            pool.shutdown(); raise
        def translate(text, cancelled):
            start = time.perf_counter()
            engine.cancelled = lambda: self.stop_event.is_set() or cancelled.is_set()
            value = memory.resolve(text, engine, self.glossary, self.profile)
            return value, (time.perf_counter()-start)*1000, memory.hits, memory.requests
        pending = job = active = previous = None
        reads = []
        skipped = 0
        stable = 0
        last_state = None
        display_id=0
        anchor = (.5,.59,.10)
        retry_digest = None
        next_retry = 0.0
        def state(value):
            nonlocal last_state
            if value != last_state:
                self.notify("capture", value); last_state = value
        try:
            while not self.stop_event.is_set():
                tick = time.monotonic()
                try:
                    frame = self.source.read()
                    capture_ms = (time.monotonic()-tick)*1000
                    roi = crop(frame.image, self.roi).convert("L")
                    digest = hashlib.blake2b(roi.tobytes(), digest_size=12).digest()
                    ocr_ms = 0.
                    if self.scheduler.should_read(roi,time.monotonic()) if self.scheduler else digest != previous:
                        start = time.perf_counter()
                        self.ocr_count+=1
                        reads = await ocr.read(roi)
                        if self.subtitles_only:
                            reads = dialogue_block(reads)
                        ocr_ms = (time.perf_counter()-start)*1000
                        previous, stable = digest, 0
                    else:
                        skipped += 1; stable += 1
                    if self.subtitles_only:
                        if reads:
                            x,y,w,h=reads[-1].box
                            anchor=(x+w/2,y+h/2,h)
                        elif retry_digest!=digest and time.monotonic()>=next_retry and hasattr(ocr,"short_dialogue"):
                            start=time.perf_counter()
                            reads=await ocr.short_dialogue(roi,anchor)
                            ocr_ms+=(time.perf_counter()-start)*1000
                            retry_digest=digest
                            next_retry=time.monotonic()+.27
                    state("ok")
                    text = " ".join(r.text for r in reads)[:1800]
                    previous_text=track.current
                    change = track.observe(text, time.monotonic())
                    if change:
                        seq, line = change
                        correction=bool(previous_text and line and len(line)>=12 and SequenceMatcher(None,previous_text,line).ratio()>=.88)
                        if line and not still_visible_prefix(previous_text,line) and not correction:display_id+=1
                        if job and not still_visible_prefix(job[1][1],line):
                            job[2].set()
                        if not active or not still_visible_prefix(active["source"],line):
                            active = None
                            # Source changes do not erase reading-time entries on TV.
                            pass
                        if line:
                            rx, ry, rw, rh = self.roi
                            x=min(r.box[0] for r in reads); y=min(r.box[1] for r in reads)
                            right=max(r.box[0]+r.box[2] for r in reads); bottom=max(r.box[1]+r.box[3] for r in reads)
                            box=(rx+x*rw,ry+y*rh,(right-x)*rw,(bottom-y)*rh)
                            pending = (seq, line, frame.timestamp, box, capture_ms, ocr_ms)
                        else:
                            pending = None; self.notify("clear", "")
                except CaptureUnavailable as err:
                    state(str(err))
                    if previous is not None:
                        if job:
                            job[2].set()
                        previous = active = pending = None
                        track.seq += 1
                        track.current = ""
                        track.empty_since = None
                        self.notify("clear","")
                if self.scheduler:self.rate=self.scheduler.rate
                self.metrics.update(ocr_attempts=self.ocr_count,skipped_ocr=skipped,ocr_per_second=round(self.ocr_count/max(.1,time.monotonic()-self.started_at),2),queue_depth=int(job is not None)+int(pending is not None),capture_width=frame.image.width if previous else 0,capture_height=frame.image.height if previous else 0)
                interval = 1/self.rate
                if stable > 8 and not self.subtitles_only:
                    interval = max(interval, min(.45, interval*1.5))
                next_frame = tick + interval
                # A finished translation can be published immediately, without
                # starting another expensive OCR pass or exceeding the sample rate.
                while (job or pending) and not self.stop_event.is_set():
                    if job is None:
                        cancelled = threading.Event()
                        job = pool.submit(translate,pending[1],cancelled), pending, cancelled
                        pending = None
                    future, info, _ = job
                    if not future.done():
                        concurrent.futures.wait([future],timeout=max(0,next_frame-time.monotonic()))
                    if not future.done():
                        break
                    job = None
                    try:
                        arabic, trans_ms, hits, count = future.result()
                    except concurrent.futures.CancelledError:
                        continue
                    seq, line, stamp, box, cap_ms, rec_ms = info
                    visible = seq == track.seq or still_visible_prefix(line,track.current)
                    if visible and not self.stop_event.is_set() and track.current:
                        now = time.time()
                        subtitle_id=f"dialogue-{display_id}"
                        if active and still_visible_prefix(active["source"],line): subtitle_id=active["id"]
                        active = envelope("subtitle_show", id=subtitle_id,update_type="new", source=line, translated=arabic,
                            source_lang="en", target_lang="ar", frame_ms=round(stamp*1000), translation_ms=round(now*1000),
                            x=box[0], y=box[1], w=box[2], h=box[3], category="text", confidence=None, font_sp=self.font,
                            duration_ms=4500, expires_at=round(now*1000)+4500)
                        self.publish(active.copy())
                        self.metrics.update(capture_ms=round(cap_ms),ocr_ms=round(rec_ms),translation_ms=round(trans_ms),latency_ms=round((now-stamp)*1000),cache_hits=hits,requests=count)
                        self.notify("result", dict(source=line, translated=arabic, latency_ms=round((now-stamp)*1000),
                            capture_ms=round(cap_ms), ocr_ms=round(rec_ms), translation_ms=round(trans_ms),
                            hits=hits, requests=count, skipped=skipped))
                self.stop_event.wait(max(.005, next_frame-time.monotonic()))
        finally:
            pool.submit(memory.close).result(); pool.shutdown()

    def stop(self):
        self.stop_event.set()


