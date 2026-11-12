from PySide6.QtCore import Qt
from PySide6.QtGui import QColor,QPainter,QFont,QPainterPath,QPen,QTextDocument,QTextCursor,QTextCharFormat,QTextBlockFormat,QTextOption
from PySide6.QtWidgets import (QWidget,QFormLayout,QVBoxLayout,QHBoxLayout,QScrollArea,
 QSpinBox,QDoubleSpinBox,QCheckBox,QComboBox,QLineEdit,QPushButton,QColorDialog,QLabel,QInputDialog)
from .display_settings import DEFAULTS,BOUNDS,validate,preset

LABELS = dict(font_family="عائلة الخط",font_size="حجم الخط (sp)",font_weight="وزن الخط",bold="عريض",
 text_color="لون النص",text_opacity="شفافية النص %",outline="حد النص",outline_color="لون حد النص",outline_width="سمك حد النص px",
 shadow="ظل النص",shadow_color="لون الظل",shadow_opacity="شفافية الظل %",shadow_x="إزاحة الظل X px",shadow_y="إزاحة الظل Y px",shadow_blur="تنعيم الظل",
 line_spacing="تباعد الأسطر px",alignment="محاذاة النص",max_width="أقصى عرض %",wrap="التفاف النص",
 background="الخلفية",background_color="لون الخلفية",background_opacity="شفافية الخلفية %",
 padding_x="حشو أفقي px",padding_y="حشو عمودي px",radius="استدارة الزوايا px",border="إطار الخلفية",
 border_color="لون الإطار",border_width="سمك الإطار px",x="إزاحة X px",y="إزاحة Y px",margin="هامش الأمان px",
 adaptive="مدة قراءة تكيفية",reading_speed="أحرف عربية في الثانية",min_seconds="أقل مدة بالثواني",max_seconds="أقصى مدة بالثواني",
 fixed_seconds="مدة ثابتة بالثواني",max_entries="أقصى جمل ظاهرة",max_height="أقصى ارتفاع للمجموعة %",older_opacity="عتامة الجمل السابقة %",spacing="المسافة بين الجمل px")

class Preview(QWidget):
    def __init__(self,parent):
        super().__init__();self.owner=parent;self.setMinimumHeight(160)
    def paintEvent(self,event):
        s=self.owner.values();p=QPainter(self);p.fillRect(self.rect(),QColor("#27343d"))
        scale=.55
        family={"sans-serif":"Segoe UI","sans-serif-medium":"Segoe UI","sans-serif-condensed":"Segoe UI","serif":"Times New Roman"}.get(s["font_family"],s["font_family"])
        font=QFont(family);font.setPixelSize(max(8,int(s["font_size"]*scale)))
        font.setWeight(QFont.Weight(max(700 if s["bold"] else 100,int(s["font_weight"]))))
        w=int(self.width()*s["max_width"]/100);x=(self.width()-w)/2+s["x"]*.12
        bottom=self.height()-12+s["y"]*.12
        for text,opacity in reversed([("جملة سابقة للمعاينة",s["older_opacity"]/100),("هذه تجربة لعرض الترجمة العربية داخل الألعاب",1)]):
            doc=QTextDocument();doc.setDocumentMargin(0);doc.setDefaultFont(font);doc.setPlainText(text)
            opt=doc.defaultTextOption();opt.setWrapMode(QTextOption.WrapMode.WordWrap if s["wrap"] else QTextOption.WrapMode.NoWrap);doc.setDefaultTextOption(opt)
            doc.setTextWidth(max(20,w-2*s["padding_x"]*scale))
            cursor=QTextCursor(doc);cursor.select(QTextCursor.SelectionType.Document)
            block=QTextBlockFormat();block.setAlignment({"center":Qt.AlignmentFlag.AlignCenter,"left":Qt.AlignmentFlag.AlignLeft,"right":Qt.AlignmentFlag.AlignRight}[s["alignment"]])
            block.setLineHeight(s["line_spacing"]*scale,QTextBlockFormat.LineHeightTypes.LineDistanceHeight.value);cursor.mergeBlockFormat(block)
            fmt=QTextCharFormat();fg=QColor(s["text_color"]);fg.setAlphaF(s["text_opacity"]/100*opacity);fmt.setForeground(fg)
            if s["outline"]:fmt.setTextOutline(QPen(QColor(s["outline_color"]),s["outline_width"]*scale))
            cursor.mergeCharFormat(fmt)
            h=doc.size().height()+2*s["padding_y"]*scale
            rect=self.rect().toRectF() if hasattr(self.rect(),"toRectF") else None
            from PySide6.QtCore import QRectF
            rect=QRectF(x,bottom-h,w,h)
            if s["background"]:
                c=QColor(s["background_color"]);c.setAlphaF(s["background_opacity"]/100*opacity);p.setBrush(c)
                p.setPen(QPen(QColor(s["border_color"]),s["border_width"]*scale) if s["border"] else Qt.PenStyle.NoPen);p.drawRoundedRect(rect,s["radius"]*scale,s["radius"]*scale)
            p.save();p.translate(x+s["padding_x"]*scale,bottom-h+s["padding_y"]*scale)
            if s["shadow"]:
                shadow=doc.clone();cur=QTextCursor(shadow);cur.select(QTextCursor.SelectionType.Document);f=QTextCharFormat()
                col=QColor(s["shadow_color"]);col.setAlphaF(s["shadow_opacity"]/100*opacity);f.setForeground(col);f.setTextOutline(QPen(Qt.PenStyle.NoPen));cur.mergeCharFormat(f)
                p.save();p.translate(s["shadow_x"]*scale,s["shadow_y"]*scale);shadow.drawContents(p);p.restore()
            if s["outline"]:doc.drawContents(p)
            fill=QTextCharFormat();fill.setForeground(fg);fill.setTextOutline(QPen(Qt.PenStyle.NoPen));cursor.mergeCharFormat(fill)
            doc.drawContents(p);p.restore();bottom-=h+s["spacing"]*scale
        p.end()

class Appearance(QWidget):
    def __init__(self,config,apply,parent=None):
        super().__init__(parent);self.apply=apply;self.controls={};self.custom=config.get("display_presets",{})
        layout=QVBoxLayout(self);row=QHBoxLayout();layout.addLayout(row)
        self.presets=QComboBox();self.presets.addItems(["Custom","Classic","Cinema","Gaming","Minimal"]+list(self.custom));row.addWidget(self.presets)
        save=QPushButton("حفظ كنمط خاص");row.addWidget(save);save.clicked.connect(self.save_preset)
        scroll=QScrollArea();scroll.setWidgetResizable(True);body=QWidget();form=QFormLayout(body);scroll.setWidget(body);layout.addWidget(scroll)
        for key,default in DEFAULTS.items():
            if isinstance(default,bool):
                c=QCheckBox();c.toggled.connect(self.changed)
            elif key in BOUNDS:
                c=QDoubleSpinBox();c.setRange(*BOUNDS[key]);c.setDecimals(0 if isinstance(default,int) else 1);c.valueChanged.connect(self.changed)
            elif key=="alignment":
                c=QComboBox();c.addItems(["center","right","left"]);c.currentTextChanged.connect(self.changed)
            else:
                c=QLineEdit();c.textChanged.connect(self.changed)
            self.controls[key]=c
            if key.endswith("color"):
                r=QHBoxLayout();r.addWidget(c);button=QPushButton("اختيار اللون");r.addWidget(button)
                button.clicked.connect(lambda _,k=key:self.pick(k));form.addRow(LABELS[key],r)
            else:form.addRow(LABELS[key],c)
        pad=QHBoxLayout();self.step=QSpinBox();self.step.setRange(1,500);self.step.setValue(1);pad.addWidget(QLabel("خطوة الحركة px"));pad.addWidget(self.step)
        for n in [1,5,10,50]:
            b=QPushButton(str(n));b.clicked.connect(lambda _,v=n:self.step.setValue(v));pad.addWidget(b)
        form.addRow(pad)
        directions=QHBoxLayout()
        for label,dx,dy in [("↑",0,-1),("↓",0,1),("←",-1,0),("→",1,0)]:
            b=QPushButton(label);b.clicked.connect(lambda _,x=dx,y=dy:self.move_anchor(x,y));directions.addWidget(b)
        form.addRow(directions)
        for text,handler in [("توسيط أفقي",lambda:self.controls["x"].setValue(0)),("إعادة الموضع",self.reset_position),("الإعداد الافتراضي",lambda:self.load(DEFAULTS))]:
            b=QPushButton(text);b.clicked.connect(handler);form.addRow(b)
        self.preview=Preview(self);layout.addWidget(self.preview)
        buttons=QHBoxLayout();layout.addLayout(buttons)
        for text,kind in [("تطبيق وحفظ","settings_sync"),("معاينة على التلفزيون","subtitle_preview_show"),("إنهاء المعاينة","subtitle_preview_hide")]:
            b=QPushButton(text);b.clicked.connect(lambda _,k=kind:self.apply(self.values(),k));buttons.addWidget(b)
        self.load(validate(config.get("display",{})))
        self.presets.currentTextChanged.connect(lambda n:self.load(self.custom.get(n,preset(n))) if n!="Custom" else None)
    def values(self):
        result={}
        for key,c in self.controls.items():
            result[key]=c.isChecked() if isinstance(c,QCheckBox) else c.value() if isinstance(c,QDoubleSpinBox) else c.currentText() if isinstance(c,QComboBox) else c.text()
        return validate(result)
    def load(self,values):
        for k,v in validate(values).items():
            if k not in self.controls:continue
            c=self.controls[k];c.blockSignals(True)
            if isinstance(c,QCheckBox):c.setChecked(v)
            elif isinstance(c,QDoubleSpinBox):c.setValue(v)
            elif isinstance(c,QComboBox):c.setCurrentText(v)
            else:c.setText(str(v))
            c.blockSignals(False)
        self.changed()
    def changed(self,*_):
        if hasattr(self,"preview"):self.preview.update()
        if hasattr(self,"preview") and all(k in self.controls for k in DEFAULTS):
            self.apply(self.values(),"live")
    def move_anchor(self,x,y):
        self.controls["x"].setValue(self.controls["x"].value()+x*self.step.value())
        self.controls["y"].setValue(self.controls["y"].value()+y*self.step.value())
    def reset_position(self):
        self.controls["x"].setValue(0);self.controls["y"].setValue(0)
    def pick(self,key):
        c=QColorDialog.getColor(QColor(self.controls[key].text()),self)
        if c.isValid():self.controls[key].setText(c.name())
    def save_preset(self):
        name,ok=QInputDialog.getText(self,"نمط الترجمة","اسم النمط")
        if ok and name.strip():
            self.custom[name.strip()]=self.values()
            if self.presets.findText(name.strip())<0:self.presets.addItem(name.strip())

