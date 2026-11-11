"""Offline Windows OCR. Windows reports word rectangles but no confidence score."""
import asyncio
from dataclasses import dataclass
from PIL import Image
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

    async def read(self, image: Image.Image) -> list[Reading]:
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
                boxes = [item.bounding_rect for item in line.words]
                if not boxes or not line.text.strip():
                    continue
                x, y = min(b.x for b in boxes), min(b.y for b in boxes)
                r, btm = max(b.x+b.width for b in boxes), max(b.y+b.height for b in boxes)
                lines.append(Reading(line.text.strip(), (x/width, y/height, (r-x)/width, (btm-y)/height)))
            return lines
        finally:
            bitmap.close()
            writer.close()

