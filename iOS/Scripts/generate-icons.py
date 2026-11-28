#!/usr/bin/env python3
"""Resample the existing opaque app artwork into explicit iPhone/iPad slots.
Maintenance only (Pillow); checked-in PNGs are used directly by Xcode.
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / 'GameLingo/Resources/Assets.xcassets/AppIcon.appiconset'


def main():
    source = Image.open(ROOT / 'AppIcon.png')
    assert source.size == (1024, 1024) and source.mode == 'RGB'
    images = []
    for idiom, slots in [('iphone', [(20, 2), (20, 3), (29, 2), (29, 3), (40, 2), (40, 3), (60, 2), (60, 3)]),
                         ('ipad', [(20, 1), (20, 2), (29, 1), (29, 2), (40, 1), (40, 2), (76, 1), (76, 2), (83.5, 2)])]:
        for size, scale in slots:
            pixels = int(size * scale)
            filename = f'Icon-{pixels}.png'
            source.resize((pixels, pixels), Image.Resampling.LANCZOS).save(ROOT / filename)
            images.append(dict(idiom=idiom, size=f'{size}x{size}', scale=f'{scale}x', filename=filename))
    images.append(dict(idiom='ios-marketing', size='1024x1024', scale='1x', filename='AppIcon.png'))
    (ROOT / 'Contents.json').write_text(json.dumps(dict(images=images, info=dict(author='xcode', version=1)), indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
