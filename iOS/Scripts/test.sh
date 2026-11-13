#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/python/bin/activate
mkdir -p build/logs
export_attachments() {
  if [[ -d build/GameLingoTests.xcresult ]]; then
    xcrun xcresulttool export attachments --path build/GameLingoTests.xcresult \
      --output-path build/logs/test-attachments || true
  fi
}
trap export_attachments EXIT
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
