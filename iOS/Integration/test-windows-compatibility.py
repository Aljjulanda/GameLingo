#!/usr/bin/env python3
"""Exercise the unchanged Windows Hub with the capability-offering OkHttp client.
Fixture PINs/tokens are passed through subprocess stdin and never logged. This is
a cross-platform protocol test, not a substitute for testing the TV receiver.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / 'desktop'))
from gamelingo.network import Hub
from gamelingo.display_settings import DEFAULTS

spec = importlib.util.spec_from_file_location('okhttp_bridge', ROOT / 'Integration/okhttp-bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    args = parser.parse_args()
    classpath = bridge.prepare()
    with tempfile.TemporaryDirectory(prefix='gamelingo-compatibility-') as temporary:
        hub = Hub(Path(temporary), args.host, lambda *_: None, port=0)
        hub.configure(dict(DEFAULTS, revision=1))
        hub.thread.start()
        try:
            assert hub.ready.wait(8) and hub.error is None, 'Windows listener failed'

            def probe(mode, **fields):
                request = dict(mode=mode, host=args.host, port=hub.port,
                               prefix=hub.fingerprint, pin=hub.pin,
                               features=['document_v1', 'speaker_v1', 'display_ack'])
                request.update(fields)
                process = subprocess.run(['java', '-cp', classpath, 'OkHttpProbe'],
                    input=json.dumps(request), text=True, capture_output=True, timeout=30)
                assert process.returncode == 0, 'OkHttp compatibility probe failed'
                result = json.loads(process.stdout)
                assert result.get('ok') is True
                return result

            paired = probe('pair')
            assert paired.get('heartbeat') is True
            resumed = probe('hello', token=paired['token'])
            assert resumed.get('heartbeat') is True
            assert probe('bad-token', token='invalid-fixture-token').get('authentication_rejected')
            assert probe('bad-fingerprint', prefix='0'*64).get('fingerprint_rejected')
            print('Unchanged Windows Hub / OkHttp 4.12.0: pair, optional features, settings ACK, heartbeat, token reconnect, bad token and wrong full fingerprint passed; no subtitle replay. Not a physical-TV test.')
        finally:
            hub.stop()


if __name__ == '__main__':
    main()
