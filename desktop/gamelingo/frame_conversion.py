"""Owned full-frame conversion. Geometry and the existing scaling policy stay fixed."""
import cv2
from PIL import Image

def owned_image(pixels,width,height,mode='RGB'):
    if width>1440:
        height=max(1,round(height*1440/width));width=1440
        pixels=cv2.resize(pixels,(width,height),interpolation=cv2.INTER_LINEAR)
    if mode=='L':
        # cvtColor allocates owned, contiguous memory. Pillow holds that owner;
        # no mapped native bytes or reusable output buffer escape the callback.
        gray=cv2.cvtColor(pixels,cv2.COLOR_BGRA2GRAY)
        return Image.fromarray(gray)
    return Image.frombytes('RGB',(width,height),pixels.tobytes(),'raw','BGRX')
