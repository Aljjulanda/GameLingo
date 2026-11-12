from types import SimpleNamespace
from pathlib import Path
import pytest
from gamelingo import capture, remoteplay


def test_active_process_selected_and_rebound(monkeypatch):
    class Process:
        def __init__(self, port):
            self.port = port
        def net_connections(self, kind):
            return [SimpleNamespace(status="ESTABLISHED", raddr=SimpleNamespace(port=self.port))]

    entries = [(200,Process(443)),(300,Process(9295))]
    monkeypatch.setattr(capture,"chiaki_windows",lambda _:entries)
    source = capture.ChiakiStreamSource("chiaki.exe")
    source.detect()
    assert source.stream.hwnd.value == 300
    entries.pop()
    source.next_check = 0
    with pytest.raises(capture.CaptureUnavailable):
        source.read()
    entries.append((400,Process(9295)))
    source.next_check = 0
    source.detect()
    assert source.stream.hwnd.value == 400


@pytest.mark.parametrize("profile",["",remoteplay.SECOND_PROFILE])
def test_each_launch_uses_explicit_registration(monkeypatch,profile):
    commands=[]
    monkeypatch.setattr(remoteplay.subprocess,"Popen",lambda args,**kw:commands.append(args))
    exe=Path("chiaki.exe")
    remoteplay.launch(exe,profile,("Living room","192.168.1.2"))
    assert commands==[["chiaki.exe","--profile",profile,"--opengl","--exit-app-on-stream-exit","stream","Living room","192.168.1.2"]]


def test_unregistered_profile_does_not_probe_or_stream(monkeypatch):
    monkeypatch.setattr(remoteplay.subprocess,"run",lambda *a,**k:SimpleNamespace(stdout=b""))
    assert remoteplay.registered_console(Path("chiaki.exe"),remoteplay.SECOND_PROFILE,"") is None


def test_background_stream_keeps_its_session_until_minimized(monkeypatch):
    import threading
    from gamelingo import window_capture
    opened=[]
    class Reader:
        def __init__(self,hwnd):
            opened.append(hwnd)
            self.closed=threading.Event()
        def read(self): return "frame from stream"
        def close(self): self.closed.set()
    source=capture.ChiakiStreamSource("chiaki.exe")
    source.stream=capture.WindowCaptureSource(700)
    monkeypatch.setattr(source,"detect",lambda:None)
    monkeypatch.setattr(window_capture,"BackgroundWindowCapture",Reader)
    monkeypatch.setattr(capture.user,"GetForegroundWindow",lambda:123)
    monkeypatch.setattr(capture.user,"IsIconic",lambda hwnd:False)
    assert source.read()==source.read()=="frame from stream"
    assert opened==[700]
    old=source.reader
    monkeypatch.setattr(capture.user,"IsIconic",lambda hwnd:True)
    with pytest.raises(capture.CaptureUnavailable):
        source.read()
    assert old.closed.is_set() and source.reader is None
