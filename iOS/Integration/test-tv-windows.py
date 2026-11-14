#!/usr/bin/env python3
"""Physical Android Receiver regression against unchanged desktop Hub.
Requires installed matching app/test APKs, authorized adb and a reachable host LAN
address. Uses isolated Android preferences and temporary desktop credentials.
Never prints fixture PIN/token. Does not certify an iPhone-to-TV connection.
"""
import argparse
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT / 'desktop'))
from gamelingo.network import Hub
from gamelingo.display_settings import DEFAULTS

parser = argparse.ArgumentParser()
parser.add_argument('--adb',required=True)
parser.add_argument('--tv',required=True,help='authorized adb serial')
parser.add_argument('--host',required=True,help='this computer LAN IPv4')
parser.add_argument('--package',default='dev.gamelingo.tv',help='application ID; use the lab variant for isolated tests')
parser.add_argument('--documents',action='store_true',help='exercise optional v1 document messages and return to dialogue')
parser.add_argument('--discovery',action='store_true',help='advertise pinned fixture via real mDNS; requires zeroconf==0.154.0')
parser.add_argument('--discovery-packages',type=pathlib.Path,help='isolated pip --target directory; does not alter the desktop environment')
args = parser.parse_args()
if args.discovery_packages:
    sys.path.insert(0,str(args.discovery_packages.resolve()))
events = []
settings_ready=threading.Event()
def notice(kind,_):
    events.append(kind)
    if kind=='settings_ack': settings_ready.set()

with tempfile.TemporaryDirectory(prefix='tv-fixture-',dir=ROOT / 'iOS/.build') as folder:
    hub = Hub(pathlib.Path(folder),args.host,notice)
    advertiser=None
    document_thread=None
    hub.configure(dict(DEFAULTS,revision=1))
    hub.thread.start()
    try:
        assert hub.ready.wait(10) and not hub.error, 'Windows fixture did not listen'
        if args.discovery:
            from zeroconf import IPVersion,ServiceInfo,Zeroconf
            advertiser=Zeroconf(interfaces=[args.host],ip_version=IPVersion.V4Only)
            service=ServiceInfo('_gamelingo._tcp.local.',f'GameLingo-{hub.fingerprint[:12]}._gamelingo._tcp.local.',
                addresses=[socket.inet_aton(args.host)],port=hub.port,server='gamelingo-fixture.local.',properties={})
            advertiser.register_service(service)
        if args.documents:
            def documents():
                if not settings_ready.wait(15): return
                messages=[dict(v=1,type='document_show',translated='هذه الصفحة الأولى. '+('اقرأ النص بهدوء. '*20),page=1,pages=2),
                          dict(v=1,type='document_show',translated='هذه الصفحة الثانية.',page=2,pages=2),
                          dict(v=1,type='document_hide'),
                          dict(v=1,type='subtitle_show',id='after-document',source='Follow me.',translated='اتبعني.',target_lang='ar',expires_at=int(time.time()*1000)+30000)]
                for message in messages:
                    hub.publish(message);time.sleep(0.6)
            document_thread=threading.Thread(target=documents,daemon=True);document_thread.start()
        code = hub.fingerprint[:12] + '-' + hub.pin
        try:
            process = subprocess.run([args.adb,'-s',args.tv,'shell','am','instrument','-w',
                '-e','host',args.host,'-e','code',code,'-e','documents',str(args.documents).lower(),'-e','discovery',str(args.discovery).lower(),
                args.package+'.test/dev.gamelingo.tv.NetworkRunner'],capture_output=True,timeout=100)
        except subprocess.TimeoutExpired:
            # TimeoutExpired.__str__ includes argv, which contains the fixture PIN.
            raise RuntimeError('Physical Android fixture timed out; arguments withheld') from None
        text = process.stdout.decode(errors='replace').replace(code,'[redacted]')
        print(text)
        assert process.returncode == 0 and 'PASS:' in text, 'Physical Android receiver fixture failed'
        assert 'settings_ack' in events, 'TV did not acknowledge Windows settings'
        print('PASS: unchanged Windows server received settings_ack from physical TV')
    finally:
        if advertiser is not None:
            advertiser.unregister_all_services();advertiser.close()
        if document_thread is not None: document_thread.join(2)
        hub.stop()
