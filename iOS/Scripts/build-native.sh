#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
SDK="${1:-iphoneos}"
ARCH="${2:-arm64}"
case "$SDK:$ARCH" in iphoneos:arm64|iphonesimulator:arm64|iphonesimulator:x86_64) ;; *) echo 'Unsupported native build platform' >&2; exit 2;; esac
SOURCES="$ROOT/.build/sources"
WORK="$ROOT/.build/native/$SDK-$ARCH"
PREFIX="$WORK/prefix"
SIGNATURE="$( { shasum -a 256 Scripts/build-native.sh Scripts/bootstrap.py Scripts/combine-libraries.py Native/GLRemotePlay.c Native/GLRemotePlay.h; xcodebuild -version; xcrun --sdk "$SDK" --show-sdk-version; echo "$SDK/$ARCH"; } | shasum -a 256 | awk '{print $1}')"
if [[ -f "$WORK/validated.sha256" && "$(cat "$WORK/validated.sha256")" == "$SIGNATURE" && -f "$ROOT/.build/lib/$SDK/libGameLingoNative.a" && -f "$ROOT/.build/include/openssl/evp.h" ]] &&
   xcrun lipo -verify_arch "$ARCH" "$ROOT/.build/lib/$SDK/libGameLingoNative.a"; then
  echo "Reusing validated native libraries: $SDK / $ARCH"
  exit 0
fi
mkdir -p "$WORK" "$PREFIX" "$ROOT/.build/lib/$SDK" "$ROOT/.build/include"
SDKROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
export SDKROOT
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
if [[ "$SDK" == iphoneos ]]; then
  OPENSSL_TARGET=ios64-xcrun
  MIN_FLAG=-miphoneos-version-min=16.0
elif [[ "$ARCH" == arm64 ]]; then
  OPENSSL_TARGET=iossimulator-arm64-xcrun
  MIN_FLAG=-mios-simulator-version-min=16.0
else
  OPENSSL_TARGET=iossimulator-x86_64-xcrun
  MIN_FLAG=-mios-simulator-version-min=16.0
fi
mkdir -p "$WORK/openssl"
OPENSSL_SIGNATURE="$( { git -C "$SOURCES/openssl" rev-parse HEAD; xcodebuild -version; echo "$OPENSSL_TARGET/$ARCH/$MIN_FLAG/no-shared/no-tests/no-apps/no-module/no-asm"; } | shasum -a 256 | awk '{print $1}')"
if [[ ! -f "$WORK/openssl.sha256" || "$(cat "$WORK/openssl.sha256")" != "$OPENSSL_SIGNATURE" || ! -f "$PREFIX/lib/libcrypto.a" ]]; then
(
  cd "$WORK/openssl"
  # Current OpenSSL LTS, not upstream's obsolete mbedTLS 2.28.0 pin.
  perl "$SOURCES/openssl/Configure" "$OPENSSL_TARGET" no-shared no-tests no-apps no-module no-asm \
    --prefix="$PREFIX" --libdir=lib "-arch $ARCH" "$MIN_FLAG"
  make -j3 build_libs
  make install_dev
)
echo "$OPENSSL_SIGNATURE" > "$WORK/openssl.sha256"
fi
test -f "$PREFIX/lib/libcrypto.a"
test -f "$PREFIX/include/openssl/ssl.h"
COMMON=(-G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$SDKROOT" -DCMAKE_OSX_ARCHITECTURES="$ARCH"
  -DCMAKE_SYSTEM_PROCESSOR="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=OFF)
cmake -S "$SOURCES/pylux" -B "$WORK/chiaki" "${COMMON[@]}" \
  -DCHIAKI_ENABLE_IOS=ON -DCHIAKI_LIB_ENABLE_OPUS=OFF -DCHIAKI_ENABLE_SPEEX=OFF \
  -DCHIAKI_USE_SYSTEM_NANOPB=OFF -DCHIAKI_USE_SYSTEM_JERASURE=OFF \
  -DCHIAKI_USE_SYSTEM_CURL=OFF -DCHIAKI_ENABLE_STEAMWORKS=OFF \
  -DOPENSSL_ROOT_DIR="$PREFIX" -DOPENSSL_USE_STATIC_LIBS=TRUE \
  -DOPENSSL_INCLUDE_DIR="$PREFIX/include" -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
  -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
  -DPYTHON_EXECUTABLE="$(command -v python3)" -DGAMELINGO_BRIDGE="$ROOT/Native/GLRemotePlay.c" \
  -DCURL_USE_SECTRANSP=ON -DCURL_USE_OPENSSL=OFF -DCURL_USE_LIBPSL=OFF \
  -DCURL_USE_LIBSSH2=OFF -DCURL_ZLIB=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF
cmake --build "$WORK/chiaki" --target chiaki-lib -j3
if [[ "$ARCH" == arm64 ]]; then RUY=ON; else RUY=OFF; fi
cmake -S "$SOURCES/ctranslate2" -B "$WORK/ct2" "${COMMON[@]}" \
  -DBUILD_CLI=OFF -DBUILD_TESTS=OFF -DWITH_MKL=OFF -DWITH_DNNL=OFF -DWITH_CUDA=OFF \
  -DWITH_ACCELERATE=ON -DWITH_RUY="$RUY" -DOPENMP_RUNTIME=NONE \
  -DENABLE_CPU_DISPATCH=ON -DRUY_MINIMAL_BUILD=ON -DCPUINFO_BUILD_TOOLS=OFF \
  -DCPUINFO_BUILD_UNIT_TESTS=OFF -DCPUINFO_BUILD_MOCK_TESTS=OFF -DCPUINFO_BUILD_BENCHMARKS=OFF
cmake --build "$WORK/ct2" --target ctranslate2 -j3
cmake -S "$SOURCES/sentencepiece" -B "$WORK/spm" "${COMMON[@]}" \
  -DSPM_ENABLE_SHARED=OFF -DSPM_BUILD_TEST=OFF -DSPM_ENABLE_TCMALLOC=OFF
cmake --build "$WORK/spm" --target sentencepiece-static -j3
# Only archives produced for requested library targets are combined, never tools or tests.
python3 Scripts/combine-libraries.py "$WORK" "$ROOT/.build/lib/$SDK/libGameLingoNative.a"
cp -R "$SOURCES/ctranslate2/include/." "$ROOT/.build/include/"
cp "$SOURCES/sentencepiece/src/sentencepiece_processor.h" "$ROOT/.build/include/"
cp "$SOURCES/sentencepiece/src/sentencepiece_model.pb.h" "$ROOT/.build/include/" 2>/dev/null || true
cp -R "$PREFIX/include/openssl" "$ROOT/.build/include/"
echo "$SIGNATURE" > "$WORK/validated.sha256"
echo "Native libraries ready: $SDK / $ARCH"
