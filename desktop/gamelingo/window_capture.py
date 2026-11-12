"""Windows Graphics Capture for a single explicitly selected chiaki window."""
import threading
import time
from .frame_conversion import owned_image
from windows_capture import WindowsCapture
from .capture import CaptureUnavailable, Frame


class BackgroundWindowCapture:
    def __init__(self, hwnd):
        self.hwnd = hwnd
        self.latest = None
        self.pixel_format='RGB'
        self.metrics={'native_callbacks':0,'converted_frames':0,'conversion_total_ms':0.,'conversion_peak_ms':0.}
        self.needed = threading.Event()
        self.ready = threading.Event()
        self.closed = threading.Event()
        self.needed.set()
        self.capture = WindowsCapture(window_hwnd=hwnd, cursor_capture=False)

        @self.capture.event
        def on_frame_arrived(frame, _control):
            self.metrics['native_callbacks']+=1
            # Copy only the frames requested by the OCR worker. The mapped GPU
            # buffer belongs to this callback and must not outlive it.
            if not self.needed.is_set() or self.closed.is_set():
                return
            self.needed.clear()
            stamp = time.time()
            begin=time.perf_counter()
            image=owned_image(frame.frame_buffer,frame.width,frame.height,self.pixel_format)
            elapsed=(time.perf_counter()-begin)*1000
            self.metrics['converted_frames']+=1;self.metrics['conversion_total_ms']+=elapsed
            self.metrics['conversion_peak_ms']=max(self.metrics['conversion_peak_ms'],elapsed)
            self.latest = Frame(image, stamp, "chiaki-window")
            self.ready.set()

        @self.capture.event
        def on_closed(*_):
            self.closed.set()
            self.ready.set()

        self.control = self.capture.start_free_threaded()

    def set_pixel_format(self,mode):
        if mode not in ('L','RGB'):raise ValueError('Unsupported capture format')
        self.pixel_format=mode

    def read(self):
        self.ready.clear()
        self.needed.set()
        self.ready.wait(.9 if self.latest is None else .045)
        if self.closed.is_set() or self.latest is None:
            raise CaptureUnavailable("بانتظار صورة نافذة بث PS5")
        return self.latest

    def close(self):
        self.closed.set()
        try:
            if not self.control.is_finished():
                self.control.stop()
        finally:
            self.latest = None
