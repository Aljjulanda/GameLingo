from pathlib import Path
from PyInstaller.utils.hooks import collect_submodules, collect_dynamic_libs, collect_data_files
root = Path(SPECPATH)
imports = collect_submodules('winrt')
binary = collect_dynamic_libs('ctranslate2')
a = Analysis([str(root/'main.py')], pathex=[str(root)], binaries=binary,
             datas=[(str(root/'GameLingo.ico'),'.')] + collect_data_files('winrt', includes=['**/*.pywinrt']), hiddenimports=imports,
             excludes=['PySide6.QtQml','PySide6.QtQuick','torch','matplotlib','scipy','pytest','IPython'])
# Windows 10 supplies the unversioned ICU interface used by Qt. A different ICU
# on the build host's PATH can export version-suffixed symbols under the same DLL name.
a.binaries = [item for item in a.binaries if Path(item[0]).name.lower() not in {'icuuc.dll', 'icudt78.dll'}]
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name='GameLingo', console=False,
          icon=str(root/'GameLingo.ico'), upx=False)
coll = COLLECT(exe, a.binaries, a.datas, name='GameLingo', upx=False)

