import json
import os
import socket
import threading
from pathlib import Path
import mss
from PySide6.QtCore import Qt, Signal, QObject, QTimer
from PySide6.QtGui import QPixmap, QImage
from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QTabWidget, QVBoxLayout,
    QHBoxLayout, QLabel, QPushButton, QComboBox, QFormLayout, QLineEdit, QFileDialog,
    QMessageBox, QPlainTextEdit, QSpinBox, QInputDialog)
from .storage import data_root, settings, save
from .models import install, ready, MODEL_ID
from .capture import DesktopCaptureSource, WindowCaptureSource, ImageFileSource, ChiakiStreamSource, chiaki_windows, windows, crop
from .network import Hub, local_address
from .pipeline import Pipeline
from . import remoteplay

REGIONS = {"subtitles":(0.04,.54,.92,.44), "dialogue":(.03,.45,.94,.52), "menus":(.03,.03,.94,.94), "full":(0,0,1,1)}
class Events(QObject):
    signal = Signal(str,object)

class MainWindow(QMainWindow):
    def __init__(self, root=None):
        super().__init__()
        self.root = root or data_root()
        self.root.mkdir(parents=True,exist_ok=True)
        self.cfg=settings(self.root)
        self.english=self.cfg.get("ui")=="en"
        self.events=Events(); self.events.signal.connect(self.on_status)
        self.hub=self.pipeline=None; self.busy=False; self.closing=False
        self.models=Path(self.cfg.get("models",self.root/"models"))
        self.profile_data=self.cfg.get("profiles",{"Default":{}})
        self.logs=[]; self.sources={}
        self.setWindowTitle("GameLingo Desktop")
        self.setMinimumSize(700,540); self.resize(850,660)
        self.setLayoutDirection(Qt.LayoutDirection.LeftToRight if self.english else Qt.LayoutDirection.RightToLeft)
        main=QWidget(); self.setCentralWidget(main); layout=QVBoxLayout(main)
        heading=QLabel("GameLingo"); heading.setObjectName("brand"); layout.addWidget(heading)
        self.tabs=QTabWidget(); layout.addWidget(self.tabs)
        self.dashboard=QWidget(); self.tabs.addTab(self.dashboard,self.tr2("الترجمة","Translation"))
        panel=QVBoxLayout(self.dashboard)
        self.state=QLabel(); self.netstate=QLabel(self.tr2("التلفزيون · غير متصل","TV · disconnected"))
        panel.addWidget(self.state); panel.addWidget(self.netstate)
        self.original=QLabel(); self.original.setWordWrap(True)
        self.subtitle=QLabel(self.tr2("في انتظار نص اللعبة","Waiting for game text")); self.subtitle.setObjectName("subtitle")
        self.subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter); self.subtitle.setWordWrap(True)
        self.subtitle.setTextFormat(Qt.TextFormat.PlainText); self.original.setTextFormat(Qt.TextFormat.PlainText)
        panel.addStretch(); panel.addWidget(self.original); panel.addWidget(self.subtitle); panel.addStretch()
        self.stats=QLabel(); self.stats.setWordWrap(True); panel.addWidget(self.stats)
        row=QHBoxLayout(); panel.addLayout(row)
        self.play=self.btn(row,"بدء الترجمة","Start translation",self.start)
        self.halt=self.btn(row,"إيقاف","Stop",self.stop); self.halt.setEnabled(False)
        f=self.form("المصدر والملف","Capture & profile")
        self.src=QComboBox(); f.addRow(self.tr2("مصدر الصورة","Frame source"),self.src); self.refresh_sources()
        self.broadcast_profile=QComboBox()
        self.broadcast_profile.addItem(self.tr2("الحساب الأول","First account"),"")
        self.broadcast_profile.addItem(self.tr2("الحساب الثاني","Second account"),remoteplay.SECOND_PROFILE)
        self.broadcast_profile.setCurrentIndex(max(0,self.broadcast_profile.findData(self.cfg.get("broadcast_profile",""))))
        f.addRow(self.tr2("حساب بث chiaki-ng","chiaki-ng streaming account"),self.broadcast_profile)
        bar=QHBoxLayout();f.addRow(bar); self.btn(bar,"تحديث النوافذ","Refresh windows",self.refresh_sources)
        self.btn(bar,"اختيار صورة…","Choose image…",self.choose_image)
        self.open_stream=self.btn(bar,"فتح بث PS5","Open PS5 stream",self.open_chiaki)
        self.btn(bar,"معاينة بعد ٣ ثوانٍ","Preview after 3 s",self.preview)
        self.preview_label=QLabel();self.preview_label.setAlignment(Qt.AlignmentFlag.AlignCenter);f.addRow(self.preview_label)
        self.profile=QComboBox();self.profile.addItems(self.profile_data);f.addRow(self.tr2("ملف اللعبة","Game profile"),self.profile)
        profiles=QHBoxLayout(); f.addRow(profiles);self.btn(profiles,"نسخ باسم…","Duplicate as…",self.duplicate)
        self.btn(profiles,"حذف الملف","Delete profile",self.delete_profile)
        self.region=QComboBox()
        for k,a,b in [("subtitles","الترجمة السفلية","Subtitles"),("dialogue","الحوار","Dialogue"),("menus","القوائم","Menus"),("full","كامل الصورة","Full frame"),("custom","مخصص","Custom")]:self.region.addItem(self.tr2(a,b),k)
        f.addRow(self.tr2("منطقة القراءة","Reading region"),self.region)
        self.custom=QLineEdit("0.04,0.62,0.92,0.35"); f.addRow(self.tr2("منطقة مخصصة · x, y, w, h","Custom ROI · x, y, w, h"),self.custom)
        self.rate=QSpinBox();self.rate.setRange(1,10);self.rate.setValue(4);f.addRow(self.tr2("عينات في الثانية","Samples per second"),self.rate)
        self.font=QSpinBox();self.font.setRange(14,48);self.font.setValue(25);f.addRow(self.tr2("حجم نص التلفزيون","TV text size"),self.font)
        self.gloss=QPlainTextEdit();self.gloss.setMaximumHeight(70);self.gloss.setPlaceholderText("Gate = البوابة")
        f.addRow(self.tr2("قاموس اللعبة · مصطلح = ترجمة","Glossary · term = translation"),self.gloss)
        self.profile.currentTextChanged.connect(self.load_profile)
        self.profile.setCurrentText(self.cfg.get("profile","Default"));self.load_profile()
        f=self.form("التلفزيون","Television")
        self.host=QComboBox();self.host.setEditable(True)
        for ip in dict.fromkeys(socket.gethostbyname_ex(socket.gethostname())[2]):
            if local_address(ip) and not ip.startswith("127."):self.host.addItem(ip)
        default_ip = self.host.currentText()
        try:
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as route:
                route.connect(("192.0.2.1",9)); routed=route.getsockname()[0]
                if local_address(routed): default_ip=routed
        except OSError: pass
        self.host.setCurrentText(self.cfg.get("host", default_ip))
        f.addRow(self.tr2("عنوان Wi-Fi للكمبيوتر","PC Wi-Fi address"),self.host)
        self.pair=QLabel();self.pair.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        self.pair.setLayoutDirection(Qt.LayoutDirection.LeftToRight); f.addRow(self.tr2("رمز التلفزيون","TV pairing code"),self.pair)
        self.listen=self.btn(f,"تشغيل استقبال التلفزيون","Start TV listener",self.listen_tv)
        self.btn(f,"قطع الاتصال","Disconnect",self.disconnect)
        tip=QLabel(self.tr2("على التلفزيون افتح GameLingo ← الاتصال بتطبيق Windows، ثم أدخل عنوان الكمبيوتر والرمز. الرمز صالح لخمس دقائق.","On the TV open GameLingo → Connect to Windows and enter this address and code. The code lasts five minutes."));tip.setWordWrap(True);f.addRow(tip)
        f=self.form("النماذج والإعدادات","Models & settings")
        self.model=QLabel(); f.addRow("English → العربية",self.model)
        self.btn(f,"تنزيل النموذج · 88.5 MB","Download model · 88.5 MB",self.download)
        self.btn(f,"اختيار مجلد النماذج…","Choose model folder…",self.choose_models)
        self.btn(f,"إزالة نموذج الإنجليزية…","Remove English model…",self.remove_model)
        self.btn(f,"مسح ذاكرة الترجمة…","Clear translation cache…",self.clear_cache)
        self.btn(f,"العربية / English","العربية / English",self.language)
        self.btn(f,"حفظ إعدادات الملف","Save profile settings",self.save_all)
        f=self.form("التشخيص","Diagnostics")
        self.diag=QPlainTextEdit();self.diag.setReadOnly(True);f.addRow(self.diag)
        self.btn(f,"تصدير تقرير…","Export report…",self.export)
        self.state.setText(self.tr2("جاهز · اختر مصدر الصورة","Ready · choose a frame source"))
        self.model_state()
        if self.cfg.get("auto_listen",(self.root/"network"/"paired.sha256").exists()):
            QTimer.singleShot(0,self.listen_tv)

    def tr2(self,a,b): return b if self.english else a
    def form(self,ar,en):
        page=QWidget(); form=QFormLayout(page); form.setFieldGrowthPolicy(QFormLayout.FieldGrowthPolicy.AllNonFixedFieldsGrow)
        self.tabs.addTab(page,self.tr2(ar,en));return form
    def btn(self,parent,ar,en,action):
        b=QPushButton(self.tr2(ar,en)); b.clicked.connect(action)
        (parent.addRow if isinstance(parent,QFormLayout) else parent.addWidget)(b); return b
    def fail(self,e): QMessageBox.warning(self,"GameLingo",str(e))
    def yes(self,msg):return QMessageBox.question(self,"GameLingo",msg)==QMessageBox.StandardButton.Yes
    def refresh_sources(self):
        old=self.src.currentData(); self.src.clear(); self.src.addItem(self.tr2("اختر مصدرًا","Select a source"),None)
        if self.cfg.get("image") and Path(self.cfg["image"]).is_file():self.src.addItem(Path(self.cfg["image"]).name,("image",self.cfg["image"]))
        self.src.addItem(self.tr2("عينة اختبار · باب مغلق","Test scene · closed door"),("sample",None))
        client=Path(self.cfg.get("chiaki",data_root()/"clients/chiaki-ng-1.10.1/chiaki-ng-Win/chiaki.exe"))
        managed={h for h,_ in chiaki_windows(client)}
        if client.is_file():
            self.src.addItem(self.tr2("بث PS5 من chiaki-ng","PS5 stream from chiaki-ng"),("chiaki",str(client)))
        for h,t in sorted(windows(),key=lambda v:"chiaki" not in v[1].lower()):
            if t!="GameLingo Desktop" and h not in managed:self.src.addItem(t,("window",h))
        with mss.MSS() as cap:
            for i,m in enumerate(cap.monitors[1:],1):
                l,t,w,h=(m[k] for k in ("left","top","width","height"))
                self.src.addItem(f"{self.tr2('شاشة','Display')} {i} · {w} × {h}",("display",(l,t,l+w,t+h)))
        for i in range(self.src.count()):
            if self.src.itemData(i)==old:self.src.setCurrentIndex(i); break
        if self.src.currentIndex()==0:
            for i in range(self.src.count()):
                if "chiaki" in self.src.itemText(i).lower():
                    self.src.setCurrentIndex(i);break
    def open_chiaki(self):
        path=Path(self.cfg.get("chiaki",data_root()/"clients/chiaki-ng-1.10.1/chiaki-ng-Win/chiaki.exe"))
        if not path.is_file():
            selected,_=QFileDialog.getOpenFileName(self,"chiaki-ng","","chiaki-ng (chiaki.exe)")
            if not selected:return
            path=Path(selected);self.cfg["chiaki"]=str(path);self.save_all()
        existing=ChiakiStreamSource(path)
        existing.detect()
        if existing.stream:
            existing.activate()
            return
        profile=self.broadcast_profile.currentData()
        local_ip=self.host.currentText().strip()
        self.save_all()
        self.open_stream.setEnabled(False)
        def lookup():
            try:
                console=remoteplay.registered_console(path,profile,local_ip)
                self.events.signal.emit("open_stream",(path,profile,console))
            except Exception as err:
                self.events.signal.emit("stream_error",str(err))
        threading.Thread(target=lookup,daemon=True).start()
    def source(self):
        value=self.src.currentData()
        if not value:raise ValueError(self.tr2("اختر نافذة البث أو شاشة أو صورة من تبويب المصدر.","Choose a window, display or image on the Capture tab."))
        typ,arg=value
        if typ=="sample":
            from .diagnostics import SampleSource
            return SampleSource()
        return {"image":ImageFileSource,"display":DesktopCaptureSource,"window":WindowCaptureSource,"chiaki":ChiakiStreamSource}[typ](arg)
    def choose_image(self):
        f,_=QFileDialog.getOpenFileName(self,"GameLingo","","Images (*.png *.jpg *.jpeg *.bmp *.webp)")
        if f:self.cfg["image"]=f;self.refresh_sources();self.src.setCurrentIndex(1)
    def roi(self):
        if self.region.currentData()!="custom":return REGIONS[self.region.currentData()]
        from PIL import Image
        values=tuple(float(n.strip()) for n in self.custom.text().split(","))
        crop(Image.new("L",(8,8)),values)
        return values
    def preview(self):
        try: source,roi=self.source(),self.roi()
        except Exception as err:self.fail(err);return
        def task():
            import time
            try:
                time.sleep(3)
                im=crop(source.read().image,roi).convert("RGB");im.thumbnail((420,145))
                self.events.signal.emit("preview",QImage(im.tobytes(),im.width,im.height,im.width*3,QImage.Format.Format_RGB888).copy())
            except Exception as e:self.events.signal.emit("error",str(e))
            finally:
                if hasattr(source,"close"):source.close()
        threading.Thread(target=task,daemon=True).start()
    def profile_settings(self):
        return dict(region=self.region.currentData(),custom=self.custom.text(),rate=self.rate.value(),font=self.font.value(),gloss=self.gloss.toPlainText())
    def load_profile(self,*_):
        d=self.profile_data.get(self.profile.currentText(),{}); self.region.setCurrentIndex(max(0,self.region.findData(d.get("region","subtitles"))))
        self.custom.setText(d.get("custom","0.04,0.62,0.92,0.35"));self.rate.setValue(d.get("rate",4));self.font.setValue(d.get("font",25));self.gloss.setPlainText(d.get("gloss",""))
    def duplicate(self):
        name,ok=QInputDialog.getText(self,"GameLingo",self.tr2("اسم ملف اللعبة","Game profile name"))
        if ok and name.strip() and name.strip() not in self.profile_data:
            name=name.strip(); self.profile_data[name]=self.profile_settings();self.profile.addItem(name);self.profile.setCurrentText(name);self.save_all()
    def delete_profile(self):
        name=self.profile.currentText()
        if name!="Default" and self.yes(self.tr2("حذف ملف اللعبة؟","Delete this profile?")):
            del self.profile_data[name];self.profile.removeItem(self.profile.currentIndex());self.save_all()
    def save_all(self):
        self.cfg["broadcast_profile"]=self.broadcast_profile.currentData()
        self.profile_data[self.profile.currentText()]=self.profile_settings()
        self.cfg.update(profile=self.profile.currentText(),profiles=self.profile_data,models=str(self.models),host=self.host.currentText())
        save(self.root,self.cfg)
    def language(self):
        self.cfg["ui"]="ar" if self.english else "en";self.save_all()
        QMessageBox.information(self,"GameLingo",self.tr2("أعد فتح التطبيق لتطبيق اللغة.","Reopen GameLingo to apply the language."))
    def model_state(self):self.model.setText((self.tr2("مثبت · جاهز دون إنترنت","Installed · offline ready") if ready(self.models) else self.tr2("غير مثبت","Not installed"))+" · Argos 1.0")
    def choose_models(self):
        if self.pipeline or self.busy:return
        f=QFileDialog.getExistingDirectory(self,"Models",str(self.models))
        if f:self.models=Path(f);self.model_state();self.save_all()
    def download(self):
        if self.busy or ready(self.models) or not self.yes(self.tr2("تنزيل 88.5 MB من Argos؟","Download 88.5 MB from Argos?")):return
        self.busy=True;self.model.setText(self.tr2("جارٍ التنزيل…","Downloading…"))
        def task():
            try:install(self.models)
            except Exception as err:self.events.signal.emit("error",str(err))
            finally:self.events.signal.emit("model",None)
        threading.Thread(target=task,daemon=True).start()
    def remove_model(self):
        if self.pipeline or self.busy:return
        if ready(self.models) and self.yes(self.tr2("إزالة نموذج الإنجليزية من المجلد المحدد؟","Remove the English model from this folder?")):
            # Remove only the pinned package files managed by GameLingo.
            from .models import FILES
            folder=self.models/MODEL_ID
            for name in FILES:(folder/name).unlink(missing_ok=True)
            for item in (folder/"model",folder):
                try:item.rmdir()
                except OSError:pass
            self.model_state()
    def clear_cache(self):
        if self.pipeline:return
        if self.yes(self.tr2("حذف الترجمات المخزنة؟","Delete cached translations?")):
            from .translation import Memory
            db=Memory(self.root/"memory.sqlite");db.db.execute("DELETE FROM memory");db.db.commit();db.close()
    def listen_tv(self):
        if self.hub:return
        try:
            self.hub=Hub(self.root/"network",self.host.currentText().strip(),self.events.signal.emit)
            self.pair.setText(self.hub.fingerprint[:12]+"-"+self.hub.pin);self.hub.thread.start()
            self.cfg["auto_listen"]=True
            self.listen.setEnabled(False);self.save_all()
        except Exception as err:self.hub=None;self.fail(err)
    def disconnect(self):
        if self.hub:self.hub.stop();self.hub=None
        self.listen.setEnabled(True);self.pair.clear();self.netstate.setText(self.tr2("التلفزيون · غير متصل","TV · disconnected"))
        if not self.closing:self.cfg["auto_listen"]=False
    def start(self):
        if self.pipeline:return
        try:
            if not ready(self.models):raise ValueError(self.tr2("ثبّت النموذج من الإعدادات أولًا.","Install the model in Settings first."))
            source,roi=self.source(),self.roi()
            glossary={}
            for line in self.gloss.toPlainText().splitlines():
                if not line.strip():continue
                k,sep,v=line.partition("=")
                if not sep or not k.strip() or not v.strip():raise ValueError("Glossary · term = translation")
                glossary[k.strip()]=v.strip()
            self.save_all()
            def publish(m):
                hub=self.hub
                if hub:hub.publish(m)
            self.pipeline=Pipeline(source,roi,self.rate.value(),self.models,self.root/"memory.sqlite",glossary,self.profile.currentText(),self.events.signal.emit,publish,self.font.value(),subtitles_only=self.region.currentData()=="subtitles")
            self.play.setEnabled(False);self.halt.setEnabled(True);self.pipeline.thread.start();self.tabs.setCurrentIndex(0)
            if isinstance(source,WindowCaptureSource):source.activate()
        except Exception as err:self.fail(err)
    def stop(self):
        if self.pipeline:self.pipeline.stop();self.halt.setEnabled(False)
    def on_status(self,kind,payload=None):
        if kind in ("open_stream","stream_error"):
            self.open_stream.setEnabled(True)
            if kind=="stream_error":
                self.fail(payload)
                return
            path,profile,console=payload
            try:
                remoteplay.launch(path,profile,console)
            except OSError as err:
                self.fail(err)
            return
        if kind=="preview":self.preview_label.setPixmap(QPixmap.fromImage(payload));return
        if kind=="model":self.busy=False;self.model_state();return
        if kind=="result":
            self.original.setText(payload["source"]);self.subtitle.setText(payload["translated"])
            self.stats.setText(f"{payload['latency_ms']} ms · OCR {payload['ocr_ms']} ms · MT {payload['translation_ms']} ms · Cache {payload['hits']}/{payload['requests']}")
        elif kind=="clear":self.original.clear();self.subtitle.clear()
        elif kind=="capture":self.state.setText(self.tr2("التقاط نشط · Windows OCR · EN → AR","Capturing · Windows OCR · EN → AR") if payload=="ok" else payload)
        elif kind=="stopped":
            self.pipeline=None;self.play.setEnabled(True);self.halt.setEnabled(False);self.state.setText(self.tr2("متوقف","Stopped"))
            self.original.clear();self.subtitle.clear()
            if self.closing:QTimer.singleShot(0,self.close)
        elif kind in ("listening","connected","disconnected"):
            labels={"listening":self.tr2("بانتظار التلفزيون","Waiting for TV"),"connected":self.tr2("التلفزيون متصل","TV connected"),"disconnected":self.tr2("التلفزيون غير متصل","TV disconnected")}
            self.netstate.setText(labels[kind]+" "+str(payload))
            if kind=="connected":self.pair.clear()
        elif kind=="error":
            self.state.setText(str(payload))
            if self.hub and self.hub.error:self.disconnect()
        if kind in ("error","listening","connected","disconnected","stopped"):
            import datetime
            line=datetime.datetime.now().strftime("%H:%M:%S")+"  "+kind+(" · "+str(payload)[:240] if kind=="error" else "")
            self.logs=(self.logs+[line])[-100:];self.diag.setPlainText("\n".join(self.logs))
    def export(self):
        path,_=QFileDialog.getSaveFileName(self,"GameLingo","GameLingo-diagnostics.txt","Text (*.txt)")
        if path:Path(path).write_text("GameLingo 0.2\n"+"\n".join(self.logs),encoding="utf-8")
    def closeEvent(self,e):
        if self.pipeline:
            self.closing=True;self.stop();e.ignore();return
        self.closing=True;self.disconnect();self.save_all();super().closeEvent(e)

