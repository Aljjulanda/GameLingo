#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/python/bin/activate
mkdir -p build/logs
export_picker_attachments() {
  if [[ -d build/GameLingoPickerUI.xcresult ]]; then
    xcrun xcresulttool export attachments --path build/GameLingoPickerUI.xcresult \
      --output-path build/logs/picker-ui-attachments || true
  fi
}
trap export_picker_attachments EXIT
ARCH="$(uname -m)"
DESTINATION="${IOS_TEST_DESTINATION:-$(cat build/simulator-destination.txt)}"
xcodebuild build-for-testing -project GameLingo.xcodeproj -scheme GameLingoPickerUI -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGN_ENTITLEMENTS='' ARCHS="$ARCH" ONLY_ACTIVE_ARCH=YES \
  2>&1 | tee build/logs/picker-ui-build.log
DEVICE_ID="$(python3 -c 'import sys; print(next(part.split("=",1)[1] for part in sys.argv[1].split(",") if part.startswith("id=")))' "$DESTINATION")"
python3 Scripts/seed-picker-fixtures.py "$DEVICE_ID" "build/DerivedData/Build/Products/Debug-iphonesimulator/GameLingo.app"
xcodebuild test-without-building -project GameLingo.xcodeproj -scheme GameLingoPickerUI -configuration Debug \
  -destination "$DESTINATION" -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
  -resultBundlePath build/GameLingoPickerUI.xcresult \
  CODE_SIGN_ENTITLEMENTS='' ARCHS="$ARCH" ONLY_ACTIVE_ARCH=YES \
  2>&1 | tee build/logs/picker-ui-tests.log
test -d build/GameLingoPickerUI.xcresult || { echo 'Missing picker XCTest result bundle'; exit 1; }
grep -Eq 'Executed [1-9][0-9]* tests?' build/logs/picker-ui-tests.log || { echo 'No picker XCTest cases executed'; exit 1; }
