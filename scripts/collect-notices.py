"""Collect license texts from the installed wheels plus official upstream notices."""
import importlib.metadata as md
from pathlib import Path
import shutil, sys, urllib.request

dest=Path(sys.argv[1]);dest.mkdir(parents=True,exist_ok=True)
for dist in md.distributions():
    name=dist.metadata["Name"]
    for f in dist.files or []:
        p=Path(str(f)); low=p.name.lower()
        if any(t in low for t in ("license","licence","copying","notice")) and dist.locate_file(f).is_file() and p.suffix.lower() not in (".py",".pyc",".dll",".pyd",".exe"):
            out=dest/name/p.name
            out.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(dist.locate_file(f),out)
extra={
 "Qt-LGPL-3.0.txt":"https://raw.githubusercontent.com/qt/qtbase/6.10/LICENSES/LGPL-3.0-only.txt",
 "Qt-GPL-3.0.txt":"https://raw.githubusercontent.com/qt/qtbase/6.10/LICENSES/GPL-3.0-only.txt",
 "CTranslate2-MIT.txt":"https://raw.githubusercontent.com/OpenNMT/CTranslate2/master/LICENSE",
 "SentencePiece-Apache.txt":"https://raw.githubusercontent.com/google/sentencepiece/master/LICENSE",
 "OkHttp-Apache.txt":"https://raw.githubusercontent.com/square/okhttp/master/LICENSE.txt",
 "Okio-Apache.txt":"https://raw.githubusercontent.com/square/okio/master/LICENSE.txt",
 "Kotlin-Apache.txt":"https://raw.githubusercontent.com/JetBrains/kotlin/master/license/LICENSE.txt",
 "Argos-MIT.txt":"https://raw.githubusercontent.com/argosopentech/argos-translate/master/LICENSE",
}
for name,url in extra.items():
    with urllib.request.urlopen(url,timeout=30) as response: (dest/name).write_bytes(response.read())
python_license=Path(sys.base_prefix)/"LICENSE.txt"
if python_license.exists():shutil.copyfile(python_license,dest/"Python.txt")

