"""Measure displayed lines using an original, non-activating test window."""
import json
import sys
import tempfile
import time
from pathlib import Path
from PySide6.QtCore import Qt, QTimer, QObject, Signal
from PySide6.QtGui import QPainter, QColor, QFont
from PySide6.QtWidgets import QApplication, QWidget
from gamelingo.pipeline import Pipeline
from gamelingo.performance import Scheduler
from gamelingo.storage import data_root
from gamelingo.ui import REGIONS
from gamelingo.window_capture import BackgroundWindowCapture

class Scene(QWidget):
    def __init__(self):
        super().__init__()
        self.line="Ready now."
        self.counter=0
        self.setWindowTitle("GameLingo · OCR test")
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.resize(960,540)

    def paintEvent(self,_event):
        painter=QPainter(self)
        painter.fillRect(self.rect(),QColor("#26414a"))
        painter.setPen(QColor("white"))
        painter.setFont(QFont("Arial",20))
        painter.drawText(90,324,780,180,Qt.AlignmentFlag.AlignCenter,self.line)
        painter.setFont(QFont("Arial",12))
        painter.drawText(835,500,"HP "+str(self.counter))
        painter.end()

class Events(QObject):
    event=Signal(str,object)

def verify_window(path,app):

    scene=Scene();scene.show();scene.lower()
    events=Events()
    samples=[("Go!",850),("Wait here.\nI will come back.",1000),("Follow me",650),
             ("Follow me to the gate.",900),("Take the key.",850),("Run!",850)]
    started=False
    began={}
    results=[]
    errors=[]
    def advance(i):
        if i==len(samples):
            scene.line="";scene.update();QTimer.singleShot(1300,app.quit);return
        line,ms=samples[i];scene.line=line;scene.update()
        began[" ".join(line.split())]=time.monotonic()
        QTimer.singleShot(ms,lambda:advance(i+1))

    def status(kind,payload):
        nonlocal started
        if kind=="error":errors.append(payload);app.quit()
        if kind!="result":return
        line=payload["source"]
        if not started and line.startswith("Ready"):
            started=True;QTimer.singleShot(300,lambda:advance(0));return
        results.append({"ocr":line,"arabic":payload["translated"],"frame_to_ready_ms":payload["latency_ms"],
                        "visible_to_ready_ms":round((time.monotonic()-began[line])*1000) if line in began else None})

    def update_hud():
        scene.counter=(scene.counter+1)%99;scene.update()
    events.event.connect(status)
    timer=QTimer();timer.timeout.connect(update_hud);timer.start(160)
    with tempfile.TemporaryDirectory() as tmp:
        source=BackgroundWindowCapture(int(scene.winId()))
        pipe=Pipeline(source,REGIONS["subtitles"],4,data_root()/"models",Path(tmp)/"cache.sqlite",{},
                      "fixture",events.event.emit,lambda _m:None,subtitles_only=True)
        pipe.scheduler=Scheduler("Balanced",False)
        pipe.thread.start()
        QTimer.singleShot(25000,app.quit);app.exec()
        pipe.stop();pipe.thread.join(10)
    expected=[" ".join(line.split()) for line,_ in samples]
    seen={r["ocr"] for r in results}
    report={"fixture":"generated window, changing corner HUD and previously uncached English lines",
            "expected":expected,"results":results,"missed":[line for line in expected if line not in seen],
            "errors":errors,"finished":not pipe.thread.is_alive(),"warmup_seen":started,"pipeline_metrics":pipe.metrics}
    Path(path).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    return 0 if not report["missed"] and not errors and report["finished"] else 1
