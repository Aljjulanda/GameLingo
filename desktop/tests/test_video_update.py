import gc
import numpy as np
import pytest
from gamelingo.dialogue_events import DialogueEvents,same_dialogue
from gamelingo.frame_conversion import owned_image

@pytest.mark.parametrize('a,b',[("Let's go.",'Lets go!'),("Don't go",'Dont go'),('Follow me','Follow me to the gate.'),('Something happened.','Somethlng happened.')])
def test_ocr_corrections_keep_event(a,b):
    assert same_dialogue(a,b)
    e=DialogueEvents();first,_=e.observe(a,(.2,.6,.6,.1),0)
    second,update=e.observe(b,(.2,.6,.6,.1),.5)
    assert update and first==second

@pytest.mark.parametrize('a,b',[('Go!','No!'),('Wait!','What?'),('Collect 10 coins','Collect 11 coins'),('Get -10 coins','Get 10 coins'),('Come here','Stay here')])
def test_actual_changes_are_not_corrections(a,b):assert not same_dialogue(a,b)

def test_repeat_after_disappearance_and_session_namespace():
    e=DialogueEvents();first,_=e.observe('Wait!',(.2,.6,.6,.1),0)
    e.absent();second,update=e.observe('Wait!',(.2,.6,.6,.1),.5)
    assert first!=second and not update
    another=DialogueEvents();third,_=another.observe('Wait!',(.2,.6,.6,.1),0)
    assert first!=third

def test_lost_speaker_and_word_update_one_current_event():
    e=DialogueEvents();box=(.2,.7,.6,.04)
    first,_=e.observe('Captain: We should leave through the gate.',box,0)
    for i,line in enumerate(('We should leave through the gate.','Captain: We should leave through the gate.','We should leave through the gate.')):
        current,correction=e.observe(line,box,.25*(i+1))
        assert current==first and correction
    assert same_dialogue('We should leave through the gate.','We should leave the gate.')
    assert not same_dialogue('We should not enter the gate.','We should enter the gate.')
    assert not same_dialogue('Collect 10 coins before leaving.','Collect coins before leaving.')
    e.absent();again,correction=e.observe('We should leave through the gate.',box,1)
    assert again!=first and not correction

@pytest.mark.parametrize('width,height',[(1280,720),(1920,1080)])
def test_full_frame_owned_conversion_preserves_geometry_and_luma(width,height):
    a=np.random.default_rng(1).integers(0,256,(height,width+8,4),dtype=np.uint8)[:,:width,:]
    old=owned_image(a,width,height,'RGB').convert('L');new=owned_image(a,width,height,'L')
    assert old.size==new.size
    assert np.abs(np.asarray(old).astype(int)-np.asarray(new).astype(int)).max()<=1
    snapshot=new.tobytes();a[:]=0;del a;gc.collect()
    assert new.tobytes()==snapshot and new.mode=='L'
