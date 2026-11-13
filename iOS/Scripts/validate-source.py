#!/usr/bin/env python3
"""Portable checks only: this does not compile Swift or certify an IPA."""
import ast
import hashlib
import json
import pathlib
import plistlib
import runpy
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPO = ROOT.parent


def main():
    for path in (ROOT / 'Scripts').glob('*.py'):
        ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
    for path in (ROOT / 'GameLingo' / 'Resources').iterdir():
        if path.suffix in ('.plist', '.xcprivacy', '.entitlements'):
            plistlib.loads(path.read_bytes())
    ET.parse(ROOT / 'GameLingo.xcodeproj/xcshareddata/xcschemes/GameLingo.xcscheme')
    schema = json.loads((ROOT / 'GameLingo/Core/Resources/tv-display-schema.json').read_text(encoding='utf-8'))
    existing = runpy.run_path(str(REPO / 'desktop/gamelingo/display_settings.py'))
    assert schema['defaults'] == existing['DEFAULTS'], 'Display defaults diverged from Windows'
    assert schema['bounds'] == {key: list(value) for key, value in existing['BOUNDS'].items()}, 'Display bounds diverged from Windows'
    manifest = json.loads((ROOT / 'baseline-platforms.sha256.json').read_text(encoding='utf-8'))
    # Original hashes remain intact. Explicitly reviewed TV networking, rendering
    # and build changes are exempt; the Windows implementation remains protected.
    approved_tv_changes = {
        'android-tv/app/build.gradle',
        'android-tv/app/src/main/java/dev/gamelingo/tv/Receiver.kt',
        'android-tv/app/src/main/java/dev/gamelingo/tv/MainActivity.kt',
        'android-tv/app/src/main/java/dev/gamelingo/tv/SubtitleState.kt',
        'android-tv/app/src/main/java/dev/gamelingo/tv/SubtitleCanvas.kt',
        'android-tv/app/src/main/AndroidManifest.xml',
        'android-tv/app/src/main/java/dev/gamelingo/tv/OverlayService.kt',
    }
    for name, digest in manifest.items():
        if name in approved_tv_changes:
            continue
        data = (REPO / name).read_bytes()
        if pathlib.Path(name).suffix in ('.py', '.kt', '.xml', '.gradle', '.properties', '.txt', '.spec'):
            data = data.replace(b'\r\n', b'\n')
        assert hashlib.sha256(data).hexdigest() == digest, f'Existing platform changed: {name}'
    project = ROOT / 'GameLingo.xcodeproj/project.pbxproj'
    original = project.read_bytes()
    subprocess.run([sys.executable, str(ROOT / 'Scripts/generate-project.py')], check=True)
    assert project.read_bytes() == original, 'Xcode project must be regenerated after source changes'
    swift_sources = list((ROOT / 'GameLingo').rglob('*.swift'))
    assert swift_sources, 'Missing Swift application'
    assert not list((ROOT / 'GameLingo').rglob('*.mobileprovision'))
    print(f'Portable source validation passed: {len(swift_sources)} Swift files, {len(manifest) - len(approved_tv_changes)} preserved platform files; {len(approved_tv_changes)} approved TV files')


if __name__ == '__main__':
    main()
