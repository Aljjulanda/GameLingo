"""Windows Graphics Capture for a single explicitly selected chiaki window."""
import threading
import time
import cv2
from PIL import Image
from windows_capture import WindowsCapture
from .capture import CaptureUnavailable, Frame


class BackgroundWindowCapture:
    def __init__(self, hwnd):
        self.hwnd = hwnd
        self.latest = None
        self.needed = threading.Event()
        self.ready = threading.Event()
        self.closed = threading.Event()
        self.needed.set()
        self.capture = WindowsCapture(window_hwnd=hwnd, cursor_capture=False)

        @self.capture.event
        def on_frame_arrived(frame, _control):
            # Copy only the frames requested by the OCR worker. The mapped GPU
            # buffer belongs to this callback and must not outlive it.
            if not self.needed.is_set() or self.closed.is_set():
                return
            self.needed.clear()
            stamp = time.time()
            pixels = frame.frame_buffer
            # The current Remote Play feed is 720p. A maximized HiDPI window
            # can quadruple the pixel count without adding any subtitle detail.
            width, height = frame.width, frame.height
            if width > 1440:
                height = max(1, round(height * 1440 / width))
                width = 1440
                pixels = cv2.resize(pixels, (width,height), interpolation=cv2.INTER_LINEAR)
            image = Image.frombytes("RGB", (width,height), pixels.tobytes(), "raw", "BGRX")
            self.latest = Frame(image, stamp, "chiaki-window")
            self.ready.set()

        @self.capture.event
        def on_closed(*_):
            self.closed.set()
            self.ready.set()

        self.control = self.capture.start_free_threaded()

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
