"""Pinned, offline-compatible Argos package. Model weights are installed separately."""
import hashlib
import json
import os
import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path

MODEL_ID = "argos-en_ar-1.0"
URL = "https://argos-net.com/v1/translate-en_ar-1_0.argosmodel"
DIGEST = "e2a6e84337f7ebbb55f9dc61dcba3a861c0d786ae5a46fa198fd8d6473f5c775"
SIZE = 88502631
FILES = ("model/model.bin", "model/shared_vocabulary.txt", "sentencepiece.model", "metadata.json", "README.md")


def ready(root: Path) -> bool:
    return all((root / MODEL_ID / name).is_file() for name in FILES)


def install(root: Path, archive: Path | None = None) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    final = root / MODEL_ID
    if ready(root):
        return final
    with tempfile.TemporaryDirectory(dir=root) as stage:
        tmp = Path(stage)
        if archive is None:
            archive = tmp / "package"
            with urllib.request.urlopen(URL, timeout=45) as response, archive.open("wb") as out:
                while chunk := response.read(256 * 1024):
                    out.write(chunk)
                    if out.tell() > SIZE:
                        raise ValueError("Unexpected model download size")
        with archive.open("rb") as src:
            if archive.stat().st_size != SIZE or hashlib.file_digest(src, "sha256").hexdigest() != DIGEST:
                raise ValueError("Model SHA-256 mismatch")
        dest = tmp / "model-stage"
        with zipfile.ZipFile(archive) as package:
            for name in FILES:
                output = dest / name
                output.parent.mkdir(parents=True, exist_ok=True)
                with package.open("en_ar/" + name) as src, output.open("wb") as out:
                    shutil.copyfileobj(src, out)
        metadata = json.loads((dest / "metadata.json").read_text("utf-8"))
        if (metadata["from_code"], metadata["to_code"]) != ("en", "ar"):
            raise ValueError("Unexpected language pair")
        try:
            os.rename(dest, final)
        except FileExistsError:
            if not ready(root):
                raise ValueError("Incomplete model folder. Remove it in settings and retry.")
    return final

