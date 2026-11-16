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
TEST_FILTER_ARGS=()
if [[ -n "${IOS_TEST_FILTERS:-}" ]]; then
  while IFS= read -r filter; do
    [[ -z "$filter" ]] && continue
    [[ "$filter" =~ ^GameLingoTests/[A-Za-z0-9_]+(/[A-Za-z0-9_]+)?$ ]] || { echo 'Invalid focused XCTest identifier'; exit 2; }
    TEST_FILTER_ARGS+=("-only-testing:$filter")
  done <<< "$IOS_TEST_FILTERS"
  ((${#TEST_FILTER_ARGS[@]} > 0)) || { echo 'Focused test list was empty'; exit 2; }
  printf 'Focused native test identifier: %s\n' "${TEST_FILTER_ARGS[@]}"
fi
xcodebuild test-without-building -project GameLingo.xcodeproj -scheme GameLingo -configuration Debug \
  -destination "$DESTINATION" -derivedDataPath build/DerivedData \
  -resultBundlePath build/GameLingoTests.xcresult \
  CODE_SIGN_ENTITLEMENTS='' ARCHS="$ARCH" ONLY_ACTIVE_ARCH=YES "${TEST_FILTER_ARGS[@]}" \
  2>&1 | tee build/logs/apple-tests.log
if [[ -n "${IOS_TEST_FILTERS:-}" ]]; then
  grep -Eq 'Executed [1-9][0-9]* tests?' build/logs/apple-tests.log || { echo 'No focused XCTest cases executed'; exit 1; }
fi
