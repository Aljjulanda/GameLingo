#!/usr/bin/env bash
set -euo pipefail
: "${TV_HOST:?Set verified TCL address}" "${URTV_DIR:?Set existing UrTV checkout}"
export TV_PORT=5555 TV_TRIES=1 MSYS2_ARG_CONV_EXCL='*'
py="$URTV_DIR/optimize/venv/Scripts/python.exe"
tv() { "$py" "$(cygpath -w "$URTV_DIR/optimize/tv.py")" "$@"; }
identity=$(tv 'getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.product.device; getprop ro.build.version.release; settings get global device_name' | tr -d '\r')
[[ "$identity" == $'TCL\nSmart TV Pro\nG10\n12\nAljulanda TV' ]] || exit 2
tv --push-b64 "${1:?Supply test APK}" /data/local/tmp/gamelingo-canvas-test.apk
tv 'pm install -r /data/local/tmp/gamelingo-canvas-test.apk; rm -f /data/local/tmp/gamelingo-canvas-test.apk'
tv 'am instrument -w dev.gamelingo.tv.test/dev.gamelingo.tv.CanvasRunner'
tv 'pm uninstall dev.gamelingo.tv.test'
tv 'am start -W -n dev.gamelingo.tv/.MainActivity'
