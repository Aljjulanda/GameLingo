#!/usr/bin/env python3
"""Physical Android Receiver regression against unchanged desktop Hub.
Requires installed matching app/test APKs, authorized adb and a reachable host LAN
address. Uses isolated Android preferences and temporary desktop credentials.
Never prints fixture PIN/token. Does not certify an iPhone-to-TV connection.
"""
import argparse
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT / 'desktop'))
from gamelingo.network import Hub
from gamelingo.display_settings import DEFAULTS

parser = argparse.ArgumentParser()
parser.add_argument('--adb',required=True)
parser.add_argument('--tv',required=True,help='authorized adb serial')
parser.add_argument('--host',required=True,help='this computer LAN IPv4')
args = parser.parse_args()
events = []
with tempfile.TemporaryDirectory(prefix='tv-fixture-',dir=ROOT / 'iOS/.build') as folder:
    hub = Hub(pathlib.Path(folder),args.host,lambda kind,_:events.append(kind))
    hub.configure(dict(DEFAULTS,revision=1))
    hub.thread.start()
    try:
        assert hub.ready.wait(10) and not hub.error, 'Windows fixture did not listen'
        code = hub.fingerprint[:12] + '-' + hub.pin
        process = subprocess.run([args.adb,'-s',args.tv,'shell','am','instrument','-w',
            '-e','host',args.host,'-e','code',code,
            'dev.gamelingo.tv.test/dev.gamelingo.tv.NetworkRunner'],capture_output=True,timeout=60)
        text = process.stdout.decode(errors='replace').replace(code,'[redacted]')
        print(text)
        assert process.returncode == 0 and 'PASS:' in text, 'Physical Android receiver fixture failed'
        assert 'settings_ack' in events, 'TV did not acknowledge Windows settings'
        print('PASS: unchanged Windows server received settings_ack from physical TV')
    finally:
        hub.stop()
