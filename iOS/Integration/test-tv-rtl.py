#!/usr/bin/env python3
"""Capture only the opaque Lab rendering fixture on real Android TV.
The production package/preferences are never changed. No PIN/token input.
"""
import argparse
from pathlib import Path
import subprocess
import time

parser=argparse.ArgumentParser()
parser.add_argument('--adb',required=True)
parser.add_argument('--tv',required=True)
parser.add_argument('--package',default='dev.gamelingo.tv.lab')
args=parser.parse_args()
assert args.package.endswith('.lab'), 'Use an isolated Lab package'
out=Path(__file__).resolve().parents[1]/'.build/rtl021'
out.mkdir(parents=True,exist_ok=True)
command=[args.adb,'-s',args.tv]
process=subprocess.Popen(command+['shell','am','instrument','-w',args.package+'.test/dev.gamelingo.tv.Rtl021Runner'],
    stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
lines=[]
try:
    for line in process.stdout:
        lines.append(line)
        if 'rendered_image_ready=rtl021.png' in line:
            time.sleep(0.4)  # Let the attached opaque fixture commit a compositor frame.
            data=subprocess.check_output(command+['exec-out','screencap','-p'],timeout=15)
            assert data.startswith(b'\x89PNG\r\n\x1a\n')
            (out/'tcl-screen.png').write_bytes(data)
    process.wait(timeout=45)
finally:
    if process.poll() is None: process.kill();process.wait()
text=''.join(lines)
(out/'instrumentation.log').write_text(text,encoding='utf-8')
print(text)
assert process.returncode==0 and 'result=PASS:' in text and 'INSTRUMENTATION_CODE: -1' in text
image=subprocess.check_output(command+['exec-out','run-as',args.package,'cat','files/rtl021.png'],timeout=15)
assert image.startswith(b'\x89PNG\r\n\x1a\n')
(out/'canvas.png').write_bytes(image)
print('PASS: actual TCL compositor screenshot and original Canvas PNG captured from opaque Lab fixture.')
