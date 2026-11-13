#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Darwin || { echo 'Xcode and macOS are required for Apple builds.' >&2; exit 2; }
xcodebuild -version
for tool in cmake ninja protoc git perl; do command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 2; }; done
python3 -m venv .build/python
source .build/python/bin/activate
python3 -m pip install --disable-pip-version-check 'protobuf==7.36.0'
python3 Scripts/bootstrap.py
python3 Scripts/collect-notices.py
python3 Scripts/generate-project.py
xcodebuild -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile -project GameLingo.xcodeproj -scheme GameLingo
bash Scripts/build-native.sh iphoneos arm64
python3 Scripts/collect-notices.py
