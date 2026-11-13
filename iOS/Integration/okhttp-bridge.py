#!/usr/bin/env python3
"""Loopback-only test coordinator. JVM connects to the simulator's real LAN IPv4.
No request/response bodies (fixture PIN/token) are logged. Not bundled in the app.
"""
import hashlib
import http.server
import json
import os
import pathlib
import subprocess
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build' / 'okhttp-probe'
ARTIFACTS = {
    'okhttp': 'com/squareup/okhttp3/okhttp/4.12.0/okhttp-4.12.0.jar',
    'okio': 'com/squareup/okio/okio-jvm/3.6.0/okio-jvm-3.6.0.jar',
    'kotlin': 'org/jetbrains/kotlin/kotlin-stdlib/1.9.10/kotlin-stdlib-1.9.10.jar',
    'annotations': 'org/jetbrains/annotations/13.0/annotations-13.0.jar',
    'json': 'org/json/json/20240303/json-20240303.jar',
}


def prepare():
    BUILD.mkdir(parents=True, exist_ok=True)
    pins = json.loads((ROOT / 'Integration' / 'jars.sha256.json').read_text())
    jars = []
    for key, path in ARTIFACTS.items():
        target = BUILD / (key + '.jar')
        if not target.exists():
            target.write_bytes(urllib.request.urlopen('https://repo.maven.apache.org/maven2/' + path, timeout=45).read())
        assert hashlib.sha256(target.read_bytes()).hexdigest() == pins[key], f'{key} checksum mismatch'
        jars.append(str(target))
    classpath = os.pathsep.join([str(BUILD)] + jars)
    subprocess.run(['javac', '-cp', classpath, '-d', str(BUILD), str(ROOT / 'Integration' / 'OkHttpProbe.java')], check=True)
    return classpath


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'ready')
    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length < 4096: raise ValueError('length')
            data = self.rfile.read(length)
            result = subprocess.run(['java','-cp',self.server.classpath,'OkHttpProbe'], input=data+b'\n', capture_output=True, timeout=30)
            if result.returncode:
                # Never relay arbitrary process output. The throwable line contains only fixed fixture assertions.
                lines = result.stderr.decode(errors='replace').splitlines()
                reason = next((line for line in lines if line.startswith('Exception in thread')), 'probe failed')
                raise RuntimeError(reason)
            output = result.stdout
            json.loads(output)
            self.send_response(200); self.end_headers(); self.wfile.write(output)
        except Exception as error:
            self.send_response(500); self.end_headers()
            self.wfile.write(json.dumps({'ok':False,'error':str(error)}).encode())


if __name__ == '__main__':
    classpath = prepare()
    server = http.server.HTTPServer(('127.0.0.1',39999),Handler)
    server.classpath = classpath
    print('OkHttp 4.12.0 fixture bridge ready on loopback',flush=True)
    server.serve_forever()
