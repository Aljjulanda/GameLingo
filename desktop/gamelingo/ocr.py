"""Offline Windows OCR. Windows reports word rectangles but no confidence score."""
from dataclasses import dataclass
import math
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat
from winrt.windows.globalization import Language
from winrt.windows.graphics.imaging import BitmapPixelFormat, SoftwareBitmap
from winrt.windows.media.ocr import OcrEngine
from winrt.windows.storage.streams import DataWriter


@dataclass(frozen=True)
class Reading:
    text: str
    box: tuple[float, float, float, float]


class WindowsOCR:
    def __init__(self, language="en"):
        self.engine = OcrEngine.try_create_from_language(Language(language))
        if self.engine is None:
            raise RuntimeError("حزمة OCR المطلوبة غير متوفرة في Windows · OCR language pack unavailable")
        self.limit = OcrEngine.max_image_dimension

    async def read(self, image: Image.Image, *, original_from_x: int = 0) -> list[Reading]:
        image = image.convert("L")
        if max(image.size) > self.limit:
            image.thumbnail((self.limit, self.limit))
        width, height = image.size
        writer = DataWriter()
        writer.write_bytes(image.tobytes())
        bitmap = SoftwareBitmap.create_copy_from_buffer(writer.detach_buffer(), BitmapPixelFormat.GRAY8, width, height)
        try:
            result = await self.engine.recognize_async(bitmap)
            lines = []
            for line in result.lines:
                selected = [item for item in line.words if item.bounding_rect.x >= original_from_x]
                boxes = [item.bounding_rect for item in selected]
                if not boxes or not line.text.strip():
                    continue
                x, y = min(b.x for b in boxes), min(b.y for b in boxes)
                r, btm = max(b.x+b.width for b in boxes), max(b.y+b.height for b in boxes)
                text = " ".join(word.text for word in selected) if original_from_x else line.text.strip()
                lines.append(Reading(text, (x/width, y/height, (r-x)/width, (btm-y)/height)))
            return lines
        finally:
            bitmap.close()
            writer.close()

    async def short_dialogue(self, region, anchor):
        """Retry an isolated word at the caption position; discard all prompt pixels."""
        width,height=region.size
        cx,cy,line_height=anchor
        line_height=max(10,round(line_height*height))
        x0=max(0,round((cx-.20)*width)); x1=min(width,round((cx+.20)*width))
        y0=max(0,round(cy*height-line_height*1.4)); y1=min(height,round(cy*height+line_height*1.4))
        if x1<=x0 or y1<=y0:
            return []
        tile=region.crop((x0,y0,x1,y1))
        base=int(ImageStat.Stat(tile).median[0])
        mask=ImageChops.difference(tile,Image.new("L",tile.size,base)).point(lambda p:255 if p>=72 else 0)
        bounds=mask.getbbox()
        if not bounds:
            return []
        left,top,right,bottom=bounds
        w,h=right-left,bottom-top
        if h<7 or h>2*line_height or not .30*h<=w<=8*h or w>.75*tile.width:
            return []
        glyph_h=h
        margin=max(4,h//4)
        original_bottom=bottom
        left,top=max(0,left-margin),max(0,top-margin)
        right,bottom=min(tile.width,right+margin),min(tile.height,bottom+margin)
        w,h=right-left,bottom-top
        crop=tile.crop((left,top,right,bottom))
        try:
            font=ImageFont.truetype("arial.ttf",max(12,round(glyph_h*1.32)))
        except OSError:
            return []
        split=math.ceil(font.getlength("Read"))+max(8,h//3)+3
        pad=max(6,h//3)
        canvas=Image.new("L",(split+w+pad,2*pad+h),base)
        ImageDraw.Draw(canvas).text((2,pad+original_bottom-top),"Read",font=font,fill=245 if base<128 else 15,anchor="ls")
        canvas.paste(crop,(split,pad))
        # Windows OCR sometimes drops an isolated 2-character line. Only word
        # boxes wholly inside the source pixels can enter the translated text.
        result=[]
        for line in await self.read(canvas,original_from_x=split):
            if sum(c.isalpha() for c in line.text)<2:
                continue
            x,y,rw,rh=line.box
            px,py=x*canvas.width-split,y*canvas.height-pad
            if px < -.5 or px+rw*canvas.width>w+1 or py < -1 or py+rh*canvas.height>h+1:
                continue
            result.append(Reading(line.text,((x0+left+px)/width,(y0+top+py)/height,
                                             rw*canvas.width/width,rh*canvas.height/height)))
        return result

