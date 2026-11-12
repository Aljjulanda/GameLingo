import threading,time
import pytest
from PIL import Image,ImageDraw,ImageFont
from gamelingo.ocr import Reading
from gamelingo.recognition import DialogueFilter,Presence,map_context,DEFAULT_ROI
from gamelingo.performance import Scheduler
from gamelingo.capture import Frame,crop
from gamelingo import pipeline

@pytest.mark.parametrize('line',['Run!','Wait!','Come here!','Go!','We should leave before they return.'])
def test_real_short_and_long_dialogue(line):
    r=Reading(line,(.35,.4,.3,.12))
    assert DialogueFilter().select([r])==[r]

def test_navigation_hud_prompts_and_menu_structure():
    g=DialogueFilter()
    assert g.select([Reading('AMMO 24',(.8,.3,.15,.1)),Reading('Press X to interact',(.1,.7,.7,.1))])==[]
    assert g.select([Reading(t,(.3,.1+i*.15,.4,.08)) for i,t in enumerate(['Resume game','Settings','Inventory','Quit'])])==[]
    assert g.select([Reading('Search',(.4,.4,.2,.12))])==[]

def test_conservative_side_text_requires_real_persistence():
    g=DialogueFilter();r=Reading('We are ready',(.06,.4,.2,.12))
    assert g.select([r])==[];assert g.select([r])==[r]

def test_missing_samples_are_not_disappearance():
    p=Presence();assert not p.observe([])
    for _ in range(100):assert not p.observe([],valid=False)
    assert p.observe([])
    assert not p.observe([Reading('Wait!',(.4,.5,.2,.1))])

@pytest.fixture
def qapp():
    from PySide6.QtWidgets import QApplication
    return QApplication.instance() or QApplication([])

def test_roi_excludes_hud_pixels_and_preview_transform(qapp):
    from PySide6.QtCore import QPointF
    from PySide6.QtGui import QImage
    from gamelingo.roi_editor import RegionCanvas
    im=Image.new('L',(1920,1080),0);ImageDraw.Draw(im).rectangle((0,0,1919,200),fill=255)
    assert crop(im,DEFAULT_ROI).getbbox() is None
    widget=RegionCanvas(QImage(1920,1080,QImage.Format.Format_RGB888),DEFAULT_ROI);widget.resize(800,600)
    b=widget.bounds();p=widget.point(QPointF(b.x()+b.width()*.25,b.y()+b.height()*.75))
    assert p.x()==pytest.approx(.25) and p.y()==pytest.approx(.75)

def test_context_calibration_maps_letterboxed_scaled_video_and_fails_closed():
    box=map_context((0,0,1,1),(.25,.275,.1,.09),(0,.05,1,.9),(1920,1200),(960,600),(1920,1080))
    assert box==pytest.approx((.25,.25,.1,.1))
    assert map_context((0,0,1,1),(.25,.2,.1,.1),(0,0,1,1),(1920,1200),(1920,1200),(1920,1080)) is None
    assert map_context((0,0,1,1),(.25,.2,.1,.1),(0,0,1,1),(1920,1080),None,(1920,1080)) is None

def test_gpu_counters_group_engines_instead_of_adding_different_engines():
    from gamelingo.gpu_metrics import summarize
    r=summarize([('pid_1_luid_0_phys_0_eng_0_engtype_3d',20),('pid_2_luid_0_phys_0_eng_0_engtype_3d',30),
                 ('pid_1_luid_0_phys_0_eng_1_engtype_copy',15),('pid_3_luid_0_phys_0_eng_2_engtype_3d',-1)])
    assert r['total']==50 and r['processes']=={1:20,2:30}

def test_dark_short_caption_triggers_between_periodic_checks():
    s=Scheduler();blank=Image.new('L',(700,180),230);s.should_read(blank,10)
    ImageDraw.Draw(blank).text((300,70),'Run!',font=ImageFont.truetype('arial.ttf',26),fill=10)
    assert s.should_read(blank,10.25)

def test_context_disabled_and_skips_never_clear_source(tmp_path,monkeypatch):
    calls=[];messages=[];shown=threading.Event()
    class Source:
        def read(self):return Frame(Image.new('RGB',(960,540),'#203642'),time.time(),'fixture')
    class OCR:
        def __init__(self,_):pass
        async def read(self,img):calls.append(img.size);return [Reading('Wait!',(.4,.4,.2,.12))]
    class Engine:
        def __init__(self,_):pass
        def translate(self,_):return 'انتظر!'
    monkeypatch.setattr(pipeline,'WindowsOCR',OCR);monkeypatch.setattr(pipeline,'ArgosTranslationProvider',Engine)
    p=pipeline.Pipeline(Source(),DEFAULT_ROI,8,tmp_path,tmp_path/'db',{},'fixture',lambda k,v:shown.set() if k=='result' else None,messages.append,recognition={'focus':True})
    p.scheduler=Scheduler('Performance',False);p.thread.start()
    try:assert shown.wait(4);time.sleep(.8)
    finally:p.stop();p.thread.join(5)
    assert all(w<960 and h<540 for w,h in calls)
    assert p.metrics.get('context_ocr_attempts',0)==0
    assert len([m for m in messages if m['type']=='subtitle_show'])==1
    assert not any(m['type']=='subtitle_source_gone' for m in messages)

def test_game_roi_and_appearance_survive_restart(tmp_path,qapp):
    from gamelingo.ui import MainWindow
    w=MainWindow(tmp_path);w.dialogue_roi.setText('0.2,0.6,0.6,0.3');w.save_all();w.close()
    new=MainWindow(tmp_path)
    try:
        assert new.dialogue_roi.text()=='0.2,0.6,0.6,0.3'
        assert new.appearance.values()['fit_background'] is True
        assert new.appearance.values()['max_width']==60
        assert not new.context_enabled.isChecked()
    finally:new.close()

def test_context_is_separate_mapped_bounded_and_disappears(tmp_path,monkeypatch):
    labels=threading.Event();cleared=threading.Event();messages=[];translated=[]
    class Source:
        def read(self):return Frame(Image.new('RGB',(960,540),'#203642'),time.time(),'fixture')
    class OCR:
        def __init__(self,_):pass
        async def read(self,img):
            if img.width==384:return [] if labels.is_set() else [Reading('Open',(.3,.2,.2,.1))]
            return [Reading('Wait!',(.4,.4,.2,.12))]
    class Engine:
        def __init__(self,_):pass
        def translate(self,line):translated.append(line);return 'انتظر!' if line=='Wait!' else 'افتح'
    monkeypatch.setattr(pipeline,'WindowsOCR',OCR);monkeypatch.setattr(pipeline,'ArgosTranslationProvider',Engine)
    def publish(m):
        messages.append(m)
        if m['type']=='context_show':labels.set()
        if labels.is_set() and m['type']=='context_clear':cleared.set()
    context=dict(enabled=True,confirmed=True,roi=(.3,.3,.4,.3),video=(0,0,1,1),calibrated_size=(960,540),tv_size=(1920,1080))
    p=pipeline.Pipeline(Source(),DEFAULT_ROI,8,tmp_path,tmp_path/'db',{},'fixture',lambda *_:None,publish,recognition={'focus':True,'context':context})
    p.scheduler=Scheduler('Performance',False);p.thread.start()
    try:assert labels.wait(5);assert cleared.wait(4)
    finally:p.stop();p.thread.join(5)
    label=next(m for m in messages if m['type']=='context_show')
    assert (label['x'],label['y'],label['w'],label['h'])==pytest.approx((.42,.36,.08,.03))
    assert [m['source'] for m in messages if m['type']=='subtitle_show']==['Wait!']
    assert translated.count('Open')==1
