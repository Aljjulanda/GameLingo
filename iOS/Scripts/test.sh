#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/python/bin/activate
mkdir -p build/logs
if [[ "${SKIP_CORE_TESTS:-0}" != 1 ]]; then
  swift test --parallel 2>&1 | tee build/logs/core-tests.log
fi
ARCH="$(uname -m)"
bash Scripts/build-native.sh iphonesimulator "$ARCH" 2>&1 | tee build/logs/native-simulator.log
python3 Scripts/fetch-test-model.py
if [[ -n "${IOS_TEST_DESTINATION:-}" ]]; then
  DESTINATION="$IOS_TEST_DESTINATION"
else
  python3 Scripts/prepare-simulator.py
  DESTINATION="$(cat build/simulator-destination.txt)"
fi
xcodebuild test -project GameLingo.xcodeproj -scheme GameLingo -configuration Debug \
  -destination "$DESTINATION" -derivedDataPath build/DerivedData \
  -resultBundlePath build/GameLingoTests.xcresult \
  CODE_SIGN_ENTITLEMENTS='' \
  2>&1 | tee build/logs/apple-tests.log
