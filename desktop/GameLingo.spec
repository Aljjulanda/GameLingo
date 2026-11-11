from pathlib import Path
import sys
from PyInstaller.utils.hooks import collect_submodules, collect_dynamic_libs, collect_data_files
root = Path(SPECPATH)
imports = collect_submodules('winrt')
binary = collect_dynamic_libs('ctranslate2')
runtime_data = collect_data_files('winrt', includes=['**/*.pywinrt'])
# Some Python distributions ship a public trust-policy file beside ssl.py.
# Include that runtime resource if present so SSLContext keeps its policy.
trust_policy = Path(sys.base_prefix) / 'Lib' / 'codex-rejected-cas.pem'
if trust_policy.is_file():
    runtime_data.append((str(trust_policy), '.'))
a = Analysis([str(root/'main.py')], pathex=[str(root)], binaries=binary,
             datas=[(str(root/'GameLingo.ico'),'.')] + runtime_data, hiddenimports=imports,
             excludes=['PySide6.QtQml','PySide6.QtQuick','torch','matplotlib','scipy','pytest','IPython'])
# Windows 10 supplies the unversioned ICU interface used by Qt. A different ICU
# on the build host's PATH can export version-suffixed symbols under the same DLL name.
a.binaries = [item for item in a.binaries if Path(item[0]).name.lower() not in {'icuuc.dll', 'icudt78.dll'}]
# Keep _ssl.pyd paired with the OpenSSL DLLs from its own Python distribution.
for index, (dest, src, kind) in enumerate(a.binaries):
    python_dll = Path(sys.base_prefix) / 'DLLs' / Path(dest).name
    if python_dll.is_file() and Path(dest).name.lower() in {'libcrypto-3-x64.dll','libssl-3-x64.dll'}:
        a.binaries[index] = (dest, str(python_dll), kind)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name='GameLingo', console=False,
          icon=str(root/'GameLingo.ico'), upx=False)
coll = COLLECT(exe, a.binaries, a.datas, name='GameLingo', upx=False)

