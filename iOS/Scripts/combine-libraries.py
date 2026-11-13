import pathlib
import subprocess
import sys

root, output = map(pathlib.Path, sys.argv[1:])
archives = []
for subdir in ('chiaki', 'ct2', 'spm', 'prefix/lib'):
    for path in (root / subdir).rglob('*.a'):
        if 'CMakeFiles' not in path.parts:
            archives.append(str(path.resolve()))
if not archives or not any(path.endswith('/libchiaki.a') for path in archives):
    raise SystemExit('Missing compiled Chiaki core')
if not any(path.endswith('/libctranslate2.a') for path in archives):
    raise SystemExit('Missing compiled translation engine')
output.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['xcrun', 'libtool', '-static', '-o', str(output), *sorted(set(archives))], check=True)
