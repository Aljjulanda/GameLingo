#!/usr/bin/env python3
"""Validate actual Android package/signature/test reports; emit public evidence only."""
import argparse,hashlib,json,re,subprocess,zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

def main():
    p=argparse.ArgumentParser();p.add_argument('--apk',type=Path,required=True);p.add_argument('--build-tools',type=Path,required=True);p.add_argument('--java',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
    signer='48cf8a45a37f4e5c338f98fa7d5135c7cdbaf59d50b39b8bf591a79622a28e38'
    signature=subprocess.check_output([str(a.java),'-jar',str(a.build_tools/'lib/apksigner.jar'),'verify','--verbose','--print-certs',str(a.apk)],text=True)
    assert 'Signer #1 certificate SHA-256 digest: '+signer in signature
    badging=subprocess.check_output([str(a.build_tools/'aapt.exe'),'dump','badging',str(a.apk)],text=True,encoding='utf-8')
    assert "package: name='dev.gamelingo.tv' versionCode='11' versionName='0.7.0-preview.1'" in badging
    with zipfile.ZipFile(a.apk) as archive:
        for name in archive.namelist():
            assert not name.lower().endswith(('.glpack','.sqlite','.gxt2','.jsonl','.keystore','.jks','.p12'))
            if name.endswith('.dex'):assert all(x not in archive.read(name) for x in [b'BootstrapRunner',b'Robolectric',b'CanvasRunner',b'NetworkRunner'])
    reports=list(Path('android-tv/app/build/test-results/testDebugUnitTest').glob('TEST-*.xml'));assert reports
    tests=failures=errors=skips=0
    for path in reports:
        root=ET.parse(path).getroot();tests+=int(root.attrib['tests']);failures+=int(root.attrib['failures']);errors+=int(root.attrib['errors']);skips+=int(root.attrib['skipped'])
    assert tests>=45 and failures==errors==skips==0
    subprocess.run(['git','diff','--exit-code','HEAD','--','android-tv'],capture_output=True,check=True)
    digest=hashlib.sha256(a.apk.read_bytes()).hexdigest()
    evidence=dict(package='dev.gamelingo.tv',version='0.7.0-preview.1',version_code=11,bytes=a.apk.stat().st_size,sha256=digest,signer_sha256=signer,tests=tests,failures=failures,errors=errors,skips=skips,
        android_tree=subprocess.check_output(['git','rev-parse','HEAD:android-tv'],text=True).strip(),source_commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),apk=str(a.apk.resolve()),scope='Host Robolectric/Skia unit tests; separate TCL bootstrap evidence does not certify iPhone/PS5 or HDMI gameplay')
    a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(evidence,indent=2))
    print(json.dumps(evidence,indent=2))
if __name__=='__main__':main()
