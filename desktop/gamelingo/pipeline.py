import asyncio
import concurrent.futures
import hashlib
import threading
import time
from .capture import CaptureUnavailable, crop, native_roi
from .ocr import WindowsOCR
from .tracking import Tracker, dialogue_block, still_visible_prefix
from .translation import Memory, ArgosTranslationProvider
from .dialogue_events import DialogueEvents
from .network import envelope
from .recognition import DialogueFilter, Presence, CONTEXT_TERMS, map_context, term, valid_roi


class Pipeline:
    """One OCR worker and one translator. Only the newest outstanding line is retained."""
    def __init__(self, source, roi, rate, models, db, glossary, profile, notify, publish, font=25, subtitles_only=False, recognition=None):
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
        self.recognition=recognition or {}
        if hasattr(source,'set_pixel_format'):source.set_pixel_format('L')

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
        gate=DialogueFilter(self.recognition.get("strictness","Balanced"));presence=Presence()
        focus=self.recognition.get("focus",self.subtitles_only)
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
        events=DialogueEvents()
        anchor = (.5,.59,.10)
        retry_digest = None
        next_retry = 0.0
        context_future=None;context_info=None;next_context=0.;context_current="";context_misses=0
        context_observed_key=""
        last_observation_stamp=None
        ocr_total_ms=0.
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
                    # Full-region bytes/hash are unnecessary when the small-mask scheduler is active.
                    digest = None if self.scheduler else hashlib.blake2b(roi.tobytes(), digest_size=12).digest()
                    ocr_ms = 0.
                    observed=False
                    should_read=self.scheduler.should_read(roi,time.monotonic()) if self.scheduler else digest != previous
                    if frame.timestamp!=last_observation_stamp and should_read:
                        observed=True
                        last_observation_stamp=frame.timestamp
                        start = time.perf_counter()
                        self.ocr_count+=1
                        reads = await ocr.read(roi)
                        raw_reads=bool(reads)
                        if self.subtitles_only or focus:
                            reads = gate.select(reads) if focus else dialogue_block(reads)
                            if focus and gate.pending and self.scheduler:self.scheduler.last_verify=0
                        ocr_ms = (time.perf_counter()-start)*1000
                        previous, stable = digest if digest is not None else True, 0
                    else:
                        skipped += 1; stable += 1
                    if observed and (self.subtitles_only or focus):
                        if reads:
                            x,y,w,h=reads[-1].box
                            anchor=(x+w/2,y+h/2,h)
                        elif not raw_reads and time.monotonic()>=next_retry and hasattr(ocr,"short_dialogue"):
                            start=time.perf_counter()
                            attempts=getattr(ocr,'attempts',0)
                            reads=await ocr.short_dialogue(roi,anchor)
                            self.ocr_count+=getattr(ocr,'attempts',attempts+1)-attempts
                            if focus:reads=gate.select(reads)
                            ocr_ms+=(time.perf_counter()-start)*1000
                            retry_digest=digest
                            next_retry=time.monotonic()+.27
                    if observed:
                        ocr_total_ms+=ocr_ms
                        self.metrics.update(ocr_last_ms=round(ocr_ms,2),ocr_mean_ms=round(ocr_total_ms/max(1,self.ocr_count),2))
                        if not reads and self.scheduler and self.scheduler.changed:self.scheduler.last_verify=0
                    state("ok")
                    text = " ".join(r.text for r in reads)[:1800]
                    previous_text=track.current
                    gone=presence.observe(reads,observed)
                    change = track.observe(text, time.monotonic(),grace=0) if observed and (text or gone) else None
                    event_info=None
                    if observed and text and not change:events.last_seen=time.monotonic()
                    if change:
                        seq, line = change
                        if self.scheduler:self.scheduler.activity(line,time.monotonic())
                        if line:
                            rx, ry, rw, rh = native_roi(frame.image.size,self.roi)
                            x=min(r.box[0] for r in reads); y=min(r.box[1] for r in reads)
                            right=max(r.box[0]+r.box[2] for r in reads); bottom=max(r.box[1]+r.box[3] for r in reads)
                            box=(rx+x*rw,ry+y*rh,(right-x)*rw,(bottom-y)*rh)
                            event_info=events.observe(line,box,time.monotonic())
                        correction=bool(event_info and event_info[1])
                        if job and not still_visible_prefix(job[1][1],line):
                            job[2].set()
                        if active and (not line or (line and not correction and not still_visible_prefix(active['source'],line))):
                            self.publish(envelope("subtitle_source_gone",id=active["id"]))
                        if not active or not still_visible_prefix(active["source"],line):
                            active = None
                            # Source changes do not erase reading-time entries on TV.
                            pass
                        if line:
                            pending = (seq, line, frame.timestamp, box, capture_ms, ocr_ms, event_info[0], correction)
                        else:
                            events.absent()
                            pending = None; self.notify("clear", "")
                    # Optional context costs zero OCR/model work while disabled. It uses
                    # only explicit ROIs and never enters the main dialogue stream.
                    context=self.recognition.get("context",{})
                    context_roi=valid_roi(context.get("roi"))
                    if context_roi:context_roi=native_roi(frame.image.size,context_roi)
                    calibrated=context.get("enabled") and context.get("confirmed") and context_roi and map_context((0,0,1,1),context_roi,context.get("video"),frame.image.size,context.get("calibrated_size"),context.get("tv_size"),context.get("target",(0,0,1,1)))
                    if context.get('enabled'):self.metrics['context_mapping']='calibrated' if calibrated else 'disabled: calibration mismatch'
                    if calibrated and time.monotonic()>=next_context:
                        next_context=time.monotonic()+.7
                        context_reads=await ocr.read(crop(frame.image,context_roi).convert("L"))
                        self.metrics["context_ocr_attempts"]=self.metrics.get("context_ocr_attempts",0)+1
                        candidate=next((r for r in context_reads if term(r.text) in CONTEXT_TERMS),None)
                        if candidate:
                            context_misses=0
                            mapped=map_context(candidate.box,context_roi,context["video"],frame.image.size,context["calibrated_size"],context["tv_size"],context.get("target",(0,0,1,1)))
                            key=term(candidate.text)
                            context_observed_key=key
                            if mapped and key==context_current and context_future is None:
                                self.publish(envelope("context_present",id="context-0",x=mapped[0],y=mapped[1],w=mapped[2],h=mapped[3]))
                            if mapped and key!=context_current and context_future is None and job is None and pending is None:
                                context_future=pool.submit(translate,candidate.text,threading.Event())
                                context_info=(key,mapped);context_current=key
                        else:
                            context_observed_key=""
                            context_misses+=1
                            if context_misses>=2:
                                context_current="";self.publish(envelope("context_clear"))
                    if context_future is not None and context_future.done():
                        key,mapped=context_info
                        try:
                            value,*_=context_future.result()
                            if calibrated and key==context_current and key==context_observed_key and context_misses<2:
                                self.publish(envelope("context_show",id="context-0",translated=value,target_lang="ar",x=mapped[0],y=mapped[1],w=mapped[2],h=mapped[3],duration_ms=1800))
                            else:context_current=""
                        except concurrent.futures.CancelledError:pass
                        context_future=None
                except CaptureUnavailable as err:
                    state(str(err))
                    if previous is not None:
                        if job:
                            job[2].set()
                        previous = active = pending = None
                        events.absent()
                        track.seq += 1
                        track.current = ""
                        track.empty_since = None
                        self.notify("clear","")
                if self.scheduler:self.rate=self.scheduler.rate
                self.metrics.update(ocr_attempts=self.ocr_count,skipped_ocr=skipped,ocr_per_second=round(self.ocr_count/max(.1,time.monotonic()-self.started_at),2),queue_depth=int(job is not None)+int(pending is not None),capture_width=frame.image.width if previous else 0,capture_height=frame.image.height if previous else 0,roi_pixels=roi.width*roi.height if previous else 0)
                meter=getattr(self.source,'reader',self.source)
                if hasattr(meter,'metrics') and 'converted_frames' in meter.metrics:
                    cm=meter.metrics;cnt=cm['converted_frames']
                    self.metrics.update(capture_converted_frames=cnt,capture_native_callbacks=cm['native_callbacks'],
                        capture_conversion_mean_ms=round(cm['conversion_total_ms']/max(1,cnt),2),capture_conversion_peak_ms=round(cm['conversion_peak_ms'],2))
                interval = self.scheduler.interval(time.monotonic()) if self.scheduler else 1/self.rate
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
                    seq, line, stamp, box, cap_ms, rec_ms, subtitle_id, is_update = info
                    # Prefix results are useful while a single typewriter event
                    # grows, but must never survive a disappearance/new event.
                    visible = subtitle_id == events.id and (seq == track.seq or still_visible_prefix(line,track.current))
                    if visible and not self.stop_event.is_set() and track.current:
                        now = time.time()
                        active = envelope("subtitle_update" if is_update else "subtitle_show", id=subtitle_id,update_type="correction" if is_update else "new", source=line, translated=arabic,
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


