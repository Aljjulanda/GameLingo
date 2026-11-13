#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
mkdir -p build/logs
test -f .build/lib/iphoneos/libGameLingoNative.a || { echo 'Run bash Scripts/prepare.sh first.' >&2; exit 2; }
ARCHIVE="$ROOT/build/GameLingo.xcarchive"
xcodebuild archive -project GameLingo.xcodeproj -scheme GameLingo -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath "$ROOT/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' \
  2>&1 | tee build/logs/archive.log
APP="$ARCHIVE/Products/Applications/GameLingo.app"
test -f "$APP/GameLingo"
PACKAGE="$(mktemp -d "$ROOT/build/package.XXXXXX")"
# Only remove this newly created and verified staging directory.
trap 'case "$PACKAGE" in "$ROOT"/build/package.*) rm -rf -- "$PACKAGE";; esac' EXIT
mkdir "$PACKAGE/Payload"
ditto "$APP" "$PACKAGE/Payload/GameLingo.app"
(
  cd "$PACKAGE"
  /usr/bin/zip -q -r -y GameLingo-unsigned.ipa Payload
)
mv -f "$PACKAGE/GameLingo-unsigned.ipa" "$ROOT/build/GameLingo-unsigned.ipa"
python3 Scripts/validate-ipa.py "$ROOT/build/GameLingo-unsigned.ipa"
echo "Unsigned IPA: $ROOT/build/GameLingo-unsigned.ipa"
