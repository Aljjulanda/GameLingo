"""Frames remain in memory. Window capture samples only the visible client area."""
import ctypes
import time
from ctypes import wintypes
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol
from PIL import Image, ImageGrab

user = ctypes.windll.user32
user.GetForegroundWindow.restype = wintypes.HWND
user.GetAncestor.argtypes = [wintypes.HWND, wintypes.UINT]
user.GetAncestor.restype = wintypes.HWND
user.WindowFromPoint.argtypes = [wintypes.POINT]
user.WindowFromPoint.restype = wintypes.HWND


@dataclass
class Frame:
    image: Image.Image
    timestamp: float
    source: str

    @property
    def dimensions(self):
        return self.image.size


class FrameSource(Protocol):
    def read(self) -> Frame: ...


def windows():
    result = []
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def visit(hwnd, _):
        if user.IsWindowVisible(hwnd) and user.GetWindowTextLengthW(hwnd):
            title = ctypes.create_unicode_buffer(512)
            user.GetWindowTextW(hwnd, title, len(title))
            result.append((int(hwnd), title.value))
        return True
    user.EnumWindows(callback_type(visit), 0)
    return result


class WindowCaptureSource:
    def __init__(self, hwnd):
        self.hwnd = wintypes.HWND(hwnd)
        self.name = "window"

    def activate(self):
        if user.IsIconic(self.hwnd):
            user.ShowWindow(self.hwnd, 9)
        user.SetForegroundWindow(self.hwnd)

    def read(self):
        # A visible-region grab cannot capture minimized or covered clients.
        front = user.GetForegroundWindow()
        if user.IsIconic(self.hwnd) or front != self.hwnd.value:
            raise CaptureUnavailable("اجعل نافذة المصدر في المقدمة · Bring the source window to the front")
        rect, origin = wintypes.RECT(), wintypes.POINT(0, 0)
        if not user.GetClientRect(self.hwnd, ctypes.byref(rect)) or not user.ClientToScreen(self.hwnd, ctypes.byref(origin)):
            raise CaptureUnavailable("Source window closed")
        return DesktopCaptureSource((origin.x, origin.y, origin.x + rect.right, origin.y + rect.bottom), self.name).read()


class CaptureUnavailable(Exception):
    pass


class DesktopCaptureSource:
    def __init__(self, box, name="display"):
        self.box = tuple(box)
        self.name = name

    def read(self):
        stamp = time.time()
        return Frame(ImageGrab.grab(bbox=self.box, all_screens=True).convert("RGB"), stamp, self.name)


class ImageFileSource:
    def __init__(self, path):
        self.path = Path(path)
        with Image.open(self.path) as img:
            self.image = img.convert("RGB")

    def read(self):
        return Frame(self.image, time.time(), "image")


def crop(image, roi):
    x, y, w, h = roi
    if not (0 <= x < 1 and 0 <= y < 1 and w > 0 and h > 0 and x+w <= 1.000001 and y+h <= 1.000001):
        raise ValueError("Invalid region")
    width, height = image.size
    rect = (int(x*width), int(y*height), min(width, max(int(x*width)+1, round((x+w)*width))),
            min(height, max(int(y*height)+1, round((y+h)*height))))
    return image.crop(rect)

