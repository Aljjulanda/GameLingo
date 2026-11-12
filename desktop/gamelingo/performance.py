"""One-second resource samples and bounded subtitle-region scheduling."""
import time
from collections import deque
import cv2
import numpy as np
import psutil
from PySide6.QtCore import QTimer
from PySide6.QtGui import QPainter,QColor,QPen
from PySide6.QtWidgets import QWidget,QVBoxLayout,QHBoxLayout,QLabel,QComboBox,QCheckBox
from .gpu_metrics import GPU

class Scheduler:
    CAPS={"Economy":2,"Balanced":4,"Performance":8}
    def __init__(self,mode="Balanced",automatic=True):
        self.CAPS=dict(type(self).CAPS)
        self.mode=mode;self.automatic=automatic;self.rate=self.CAPS.get(mode,4)
        self.signature=None;self.last_verify=0.;self.high=0;self.low=0;self.changed_at=0.
        self.last_activity=0.;self.has_text=False
    def activity(self,text,now):
        if bool(text)!=self.has_text:self.last_activity=now
        self.has_text=bool(text)
    def interval(self,now):
        return max(1/self.rate,.35 if now-self.last_activity>2 else 0)
    def load(self,cpu,now):
        cap=self.CAPS[self.mode]
        if not self.automatic:self.rate=cap;return
        self.high=self.high+1 if cpu>88 else 0
        self.low=self.low+1 if cpu<65 else 0
        if now-self.changed_at<8:return
        if self.high>=5:
            self.rate=max(2,self.rate-1);self.changed_at=now;self.high=0
        elif self.low>=10:
            self.rate=min(cap,self.rate+1);self.changed_at=now;self.low=0
        self.rate=min(self.rate,cap)
    def should_read(self,image,now):
        a=np.asarray(image)
        # High-contrast bright strokes in a small mask are less sensitive to
        # background motion than hashing all pixels in the subtitle region.
        small=cv2.resize(a,(256,96),interpolation=cv2.INTER_AREA)
        # Symmetric edges retain dark captions on light scenes as well as white
        # captions, without hashing moving background pixels at full resolution.
        mask=cv2.Canny(small,70,140)
        difference=1. if self.signature is None else float(np.count_nonzero(mask!=self.signature))/mask.size
        changed=difference>.0004
        self.changed=changed
        if changed:self.last_activity=now
        verify=now-self.last_verify>=(.65 if self.has_text else 1.2)
        if changed or verify:
            self.signature=mask;self.last_verify=now;return True
        return False

class Graph(QWidget):
    def __init__(self):
        super().__init__();self.samples=deque(maxlen=90);self.setMinimumHeight(100)
    def paintEvent(self,event):
        p=QPainter(self);p.fillRect(self.rect(),QColor("#14282d"));p.setPen(QPen(QColor("#63ddb9"),2))
        vals=list(self.samples)
        for i in range(1,len(vals)):
            p.drawLine(int((i-1)*self.width()/89),int(self.height()*(1-vals[i-1]/100)),
                       int(i*self.width()/89),int(self.height()*(1-vals[i]/100)))
        p.end()

class Performance(QWidget):
    def __init__(self,config,callback,pipeline):
        super().__init__();self.callback=callback;self.pipeline=pipeline
        self.scheduler=Scheduler(config.get("performance_mode","Balanced"),config.get("automatic_performance",True))
        self.scheduler.CAPS.update({k:max(1,min(8,int(v))) for k,v in config.get("performance_caps",{}).items() if k in self.scheduler.CAPS})
        self.scheduler.rate=self.scheduler.CAPS[self.scheduler.mode]
        layout=QVBoxLayout(self);row=QHBoxLayout();layout.addLayout(row)
        self.mode=QComboBox();self.mode.addItems(list(Scheduler.CAPS));self.mode.setCurrentText(self.scheduler.mode);row.addWidget(self.mode)
        self.auto=QCheckBox("إدارة تلقائية للحمل المستمر");self.auto.setChecked(self.scheduler.automatic);row.addWidget(self.auto)
        self.mode.currentTextChanged.connect(self.changed);self.auto.toggled.connect(self.changed)
        self.system=QLabel();self.process=QLabel();self.stages=QLabel()
        for w in (self.system,self.process,self.stages):w.setWordWrap(True);layout.addWidget(w)
        self.graph=Graph();layout.addWidget(self.graph);self.gpu_label=QLabel('GPU · جارٍ تهيئة عدادات Windows');self.gpu_label.setWordWrap(True);layout.addWidget(self.gpu_label)
        self.gpu=GPU();self.last_gpu=0.
        self.destroyed.connect(lambda *_:self.gpu.close())
        self.own=psutil.Process();self.own.cpu_percent();self.captures={}
        self.timer=QTimer(self);self.timer.timeout.connect(self.sample);self.timer.start(1000)
    def changed(self,*_):
        self.scheduler.mode=self.mode.currentText();self.scheduler.automatic=self.auto.isChecked()
        self.scheduler.rate=self.scheduler.CAPS[self.scheduler.mode];self.callback(self.scheduler)
    def sample(self):
        cpu=psutil.cpu_percent();mem=psutil.virtual_memory()
        self.scheduler.load(cpu,time.monotonic())
        self.system.setText(f"CPU النظام {cpu:.1f}% · RAM {mem.percent:.1f}%")
        own=self.own.cpu_percent()/psutil.cpu_count()
        details=[f"GameLingo CPU {own:.1f}% · RAM {self.own.memory_info().rss/1048576:.1f} MB"]
        active=set()
        for p in psutil.process_iter(["name"]):
            if (p.info["name"] or "").lower()!="chiaki.exe":continue
            try:
                active.add(p.pid)
                if p.pid not in self.captures:
                    self.captures[p.pid]=p;p.cpu_percent()
                else:p=self.captures[p.pid]
                details.append(f"chiaki PID {p.pid} CPU {p.cpu_percent()/psutil.cpu_count():.1f}% · RAM {p.memory_info().rss/1048576:.1f} MB")
            except psutil.Error:pass
        self.captures={pid:p for pid,p in self.captures.items() if pid in active}
        self.process.setText("\n".join(details))
        now=time.monotonic()
        if now-self.last_gpu>=2:
            self.last_gpu=now;gpu=self.gpu.sample()
            if gpu is None:self.gpu_label.setText('GPU · العدادات غير متاحة: '+self.gpu.error)
            else:
                values=gpu['processes'];lines=[f"GPU النظام {gpu['total']:.1f}% · GameLingo {values.get(self.own.pid,0):.1f}%"]
                lines.extend(f"chiaki PID {pid} GPU {values.get(pid,0):.1f}%" for pid in active)
                self.gpu_label.setText(' · '.join(lines)+' · أكثر محرك انشغالًا، عينة كل ثانيتين')
        task=self.pipeline()
        if task:
            m=task.metrics
            self.stages.setText(" · ".join(f"{k}={v}" for k,v in m.items())+f" · cap={self.scheduler.rate}/s · CPU int8 / Windows OCR")
        self.graph.samples.append(cpu);self.graph.update()

