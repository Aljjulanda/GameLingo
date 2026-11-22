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
  for result in build/GameLingoTests*.xcresult; do
    [[ -d "$result" ]] || continue
    xcrun xcresulttool export attachments --path "$result" \
      --output-path "build/logs/test-attachments/$(basename "$result" .xcresult)" || true
  done
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
# macOS ships Bash 3.2: expanding an empty array with nounset can abort
# before xcodebuild runs. Keep the command nonempty for the unfiltered route.
TEST_COMMAND=(xcodebuild test-without-building -project GameLingo.xcodeproj -scheme GameLingo -configuration Debug
  -destination "$DESTINATION" -derivedDataPath build/DerivedData
  CODE_SIGN_ENTITLEMENTS='' ARCHS="$ARCH" ONLY_ACTIVE_ARCH=YES)
if [[ "${IOS_PREVIEW:-0}" == 1 ]]; then
  IOS_TEST_FILTERS="$(python3 Scripts/preview-tests.py filters)"
  export IOS_TEST_FILTERS
fi
FILTER_COUNT=0
SHARED_COUNT=0
ISOLATED_COUNT=0
SHARED_FILTERS=()
ISOLATED_FILTERS=()
ISOLATED_IDS=''
if [[ "${IOS_ISOLATE_VISION:-0}" == 1 ]]; then
  [[ -n "${IOS_TEST_FILTERS:-}" ]] || { echo 'Vision isolation requires explicit test filters'; exit 2; }
  ISOLATED_IDS="$(python3 Scripts/preview-tests.py isolated)"
  [[ -n "$ISOLATED_IDS" ]] || { echo 'Missing isolated Vision identifiers'; exit 2; }
fi
is_isolated() {
  local identifier
  while IFS= read -r identifier; do
    [[ "$1" == "$identifier" ]] && return 0
  done <<< "$ISOLATED_IDS"
  return 1
}
if [[ -n "${IOS_TEST_FILTERS:-}" ]]; then
  while IFS= read -r filter; do
    [[ -z "$filter" ]] && continue
    [[ "$filter" =~ ^GameLingoTests/[A-Za-z0-9_]+(/[A-Za-z0-9_]+)?$ ]] || { echo 'Invalid focused XCTest identifier'; exit 2; }
    if [[ "${IOS_ISOLATE_VISION:-0}" == 1 ]]; then
      [[ "$filter" =~ ^GameLingoTests/[A-Za-z0-9_]+/[A-Za-z0-9_]+$ ]] || { echo 'Vision isolation requires individual test methods'; exit 2; }
    fi
    if [[ "${IOS_ISOLATE_VISION:-0}" == 1 ]] && is_isolated "$filter"; then
      ISOLATED_FILTERS+=("-only-testing:$filter")
      ISOLATED_COUNT=$((ISOLATED_COUNT+1))
    else
      SHARED_FILTERS+=("-only-testing:$filter")
      SHARED_COUNT=$((SHARED_COUNT+1))
    fi
    FILTER_COUNT=$((FILTER_COUNT+1))
    printf 'Focused native test identifier: %s\n' "$filter"
  done <<< "$IOS_TEST_FILTERS"
  ((FILTER_COUNT > 0)) || { echo 'Focused test list was empty'; exit 2; }
fi
: > build/logs/apple-tests.log
run_batch() {
  local bundle="$1"
  shift
  local log="build/logs/$(basename "$bundle" .xcresult).log"
  "${TEST_COMMAND[@]}" -resultBundlePath "$bundle" "$@" 2>&1 | tee "$log" | tee -a build/logs/apple-tests.log
  test -d "$bundle" || { echo 'Missing native XCTest result bundle'; exit 1; }
  grep -Eq 'Executed [1-9][0-9]* tests?' "$log" || { echo 'No native XCTest cases executed'; exit 1; }
}
if ((FILTER_COUNT == 0)); then
  run_batch build/GameLingoTests.xcresult
elif ((SHARED_COUNT > 0)); then
  run_batch build/GameLingoTests.xcresult "${SHARED_FILTERS[@]}"
fi
# Fresh test sessions avoid sharing Vision/VideoToolbox simulator driver state
# between image cases. Each selected case runs exactly once; any failure stops
# the runner. Do not retry a crash or merge a later pass over an earlier failure.
if ((ISOLATED_COUNT > 0)); then
  for ((index=0; index<ISOLATED_COUNT; index++)); do
    run_batch "build/GameLingoTests-Vision-$index.xcresult" "${ISOLATED_FILTERS[$index]}"
  done
fi

if [[ "${IOS_PREVIEW:-0}" == 1 ]]; then
  python3 Scripts/preview-tests.py verify build/logs/apple-tests.log
fi
