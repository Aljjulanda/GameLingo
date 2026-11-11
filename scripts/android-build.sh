#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/../android-tv"
: "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK}"
: "${JAVA_HOME:?Set JAVA_HOME to a JDK (17 or 21)}"
"${GRADLE_BIN:-gradle}" --console plain :app:testDebugUnitTest :app:assembleDebug "$@"

