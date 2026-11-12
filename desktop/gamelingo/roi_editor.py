"""In-memory native-frame ROI selector. No screenshot or gameplay is saved."""
from PySide6.QtCore import Qt,QRectF,QPointF
from PySide6.QtGui import QPainter,QColor,QImage,QPen
from PySide6.QtWidgets import QDialog,QVBoxLayout,QWidget,QDialogButtonBox,QLabel

class RegionCanvas(QWidget):
    def __init__(self,image,roi,parent=None):
        super().__init__(parent); self.image=image; self.roi=roi;self.origin=None
        self.setMinimumSize(600,340)
    def bounds(self):
        scale=min(self.width()/self.image.width(),self.height()/self.image.height())
        w,h=self.image.width()*scale,self.image.height()*scale
        return QRectF((self.width()-w)/2,(self.height()-h)/2,w,h)
    def point(self,p):
        b=self.bounds()
        return QPointF(max(0,min(1,(p.x()-b.x())/b.width())),max(0,min(1,(p.y()-b.y())/b.height())))
    def paintEvent(self,_):
        p=QPainter(self);p.fillRect(self.rect(),QColor('#18282e'));b=self.bounds();p.drawImage(b,self.image)
        x,y,w,h=self.roi;p.setPen(QPen(QColor('#67e6b8'),2));p.setBrush(QColor(50,220,160,35))
        p.drawRect(QRectF(b.x()+x*b.width(),b.y()+y*b.height(),w*b.width(),h*b.height()));p.end()
    def mousePressEvent(self,event):
        if event.button()==Qt.MouseButton.LeftButton:self.origin=self.point(event.position())
    def mouseMoveEvent(self,event):
        if self.origin is None:return
        p=self.point(event.position());a=self.origin
        self.roi=(min(a.x(),p.x()),min(a.y(),p.y()),max(.001,abs(a.x()-p.x())),max(.001,abs(a.y()-p.y())))
        self.update()
    def mouseReleaseEvent(self,event):self.mouseMoveEvent(event);self.origin=None

class RegionEditor(QDialog):
    def __init__(self,image,roi,parent=None):
        super().__init__(parent);self.setWindowTitle('تحديد منطقة النص');self.resize(820,520)
        layout=QVBoxLayout(self);layout.addWidget(QLabel('اسحب حول النص المطلوب فقط. المعاينة في الذاكرة ولا تُحفظ.'))
        image=image.convert('RGB');q=QImage(image.tobytes(),image.width,image.height,image.width*3,QImage.Format.Format_RGB888).copy()
        self.canvas=RegionCanvas(q,roi);layout.addWidget(self.canvas)
        layout.addWidget(QLabel(f'إحداثيات الصورة الأصلية: {image.width} × {image.height} بكسل'))
        buttons=QDialogButtonBox(QDialogButtonBox.StandardButton.Ok|QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(self.accept);buttons.rejected.connect(self.reject);layout.addWidget(buttons)
