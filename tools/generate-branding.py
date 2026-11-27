"""Render our code-owned SVG to an iOS icon and matching Android vector.

Requires Pillow. Supports the logo's M/L/H/V/C/Q/Z paths and circles.
"""
from pathlib import Path
import json
import re
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]


def polygon(data):
    tokens = re.findall(r'[MLHVCQZ]|-?\d+(?:\.\d+)?', data)
    paths, points, point = [], [], (0, 0)
    i = 0
    while i < len(tokens):
        command = tokens[i]
        i += 1
        count = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'Q': 4, 'Z': 0}[command]
        values = list(map(float, tokens[i:i + count]))
        i += count
        if command == 'Z':
            paths.append(points)
            points = []
        elif command in ('M', 'L', 'H', 'V'):
            point = (values[0], values[1]) if command in ('M', 'L') else (values[0], point[1]) if command == 'H' else (point[0], values[0])
            points.append(point)
        else:
            controls = [point] + list(zip(values[::2], values[1::2]))
            for step in range(1, 33):
                t = step / 32
                row = controls[:]
                while len(row) > 1:
                    row = [(a[0] * (1 - t) + b[0] * t, a[1] * (1 - t) + b[1] * t) for a, b in zip(row, row[1:])]
                points.append(row[0])
            point = controls[-1]
    return paths


def main():
    svg = ET.parse(ROOT / 'design/gamelingo-logo.svg').getroot()
    scale = 32
    image = Image.new('RGB', (64 * scale, 64 * scale))
    draw = ImageDraw.Draw(image)
    vector = ET.Element('vector', {'xmlns:android': 'http://schemas.android.com/apk/res/android', 'android:width': '64dp', 'android:height': '64dp', 'android:viewportWidth': '64', 'android:viewportHeight': '64'})
    for element in svg:
        kind = element.tag.split('}')[-1]
        color = element.attrib['fill']
        if kind == 'path':
            data = element.attrib['d']
            for points in polygon(data):
                draw.polygon([(x * scale, y * scale) for x, y in points], fill=color)
        elif kind == 'circle':
            x, y, radius = [float(element.attrib[key]) for key in ('cx', 'cy', 'r')]
            draw.ellipse(((x - radius) * scale, (y - radius) * scale, (x + radius) * scale, (y + radius) * scale), fill=color)
            data = f'M{x-radius},{y} a{radius},{radius} 0,1 0,{2*radius},0 a{radius},{radius} 0,1 0,{-2*radius},0'
        else:
            raise ValueError(kind)
        ET.SubElement(vector, 'path', {'android:fillColor': color, 'android:pathData': data})
    assets = ROOT / 'iOS/GameLingo/Resources/Assets.xcassets'
    icon = assets / 'AppIcon.appiconset'
    icon.mkdir(parents=True, exist_ok=True)
    (assets / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n', encoding='utf-8')
    (icon / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n', encoding='utf-8')
    image.resize((1024, 1024), Image.Resampling.LANCZOS).save(icon / 'AppIcon.png')
    ET.indent(vector, space='  ')
    (ROOT / 'android-tv/app/src/main/res/drawable/logo.xml').write_text(ET.tostring(vector, encoding='unicode') + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
