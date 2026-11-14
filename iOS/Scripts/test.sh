#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/python/bin/activate
mkdir -p build/logs
python3 Integration/okhttp-bridge.py > build/logs/okhttp-bridge.log 2>&1 &
BRIDGE_PID=$!
cleanup() {
  kill "$BRIDGE_PID" 2>/dev/null || true
  export_attachments
}
export_attachments() {
  if [[ -d build/GameLingoTests.xcresult ]]; then
    xcrun xcresulttool export attachments --path build/GameLingoTests.xcresult \
      --output-path build/logs/test-attachments || true
  fi
  if [[ -d build/GameLingoPickerUI.xcresult ]]; then
    xcrun xcresulttool export attachments --path build/GameLingoPickerUI.xcresult \
      --output-path build/logs/picker-ui-attachments || true
  fi
}
trap cleanup EXIT
for attempt in {1..60}; do
  if curl --silent --fail http://127.0.0.1:39999/ >/dev/null; then break; fi
  if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then cat build/logs/okhttp-bridge.log; exit 1; fi
  sleep 1
done
curl --silent --fail http://127.0.0.1:39999/ >/dev/null
if [[ "${SKIP_CORE_TESTS:-0}" != 1 ]]; then
  swift test --parallel 2>&1 | tee build/logs/core-tests.log
fi
ARCH="$(uname -m)"
bash Scripts/build-native.sh iphonesimulator "$ARCH" 2>&1 | tee build/logs/native-simulator.log
python3 Scripts/fetch-test-model.py
xcodebuild build-for-testing -project GameLingo.xcodeproj -scheme GameLingo -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGN_ENTITLEMENTS='' ARCHS="$ARCH" ONLY_ACTIVE_ARCH=YES \
  2>&1 | tee build/logs/apple-test-build.log
if [[ -n "${IOS_TEST_DESTINATION:-}" ]]; then
  DESTINATION="$IOS_TEST_DESTINATION"
else
  python3 Scripts/prepare-simulator.py
  DESTINATION="$(cat build/simulator-destination.txt)"
fi
xcodebuild test-without-building -project GameLingo.xcodeproj -scheme GameLingo -configuration Debug \
  -destination "$DESTINATION" -derivedDataPath build/DerivedData \
  -resultBundlePath build/GameLingoTests.xcresult \
  CODE_SIGN_ENTITLEMENTS='' ARCHS="$ARCH" ONLY_ACTIVE_ARCH=YES \
  2>&1 | tee build/logs/apple-tests.log
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
