#!/usr/bin/env bash
# Run in Git Bash on Windows. Uses the owner's authenticated UrTV ADB client.
set -euo pipefail
: "${TV_HOST:?Set the verified TCL IPv4 address}"
: "${URTV_DIR:?Set the path to the existing UrTV checkout}"
export TV_PORT="${TV_PORT:-5555}" TV_TRIES=1 MSYS2_ARG_CONV_EXCL='*'
py="$URTV_DIR/optimize/venv/Scripts/python.exe"
tv() { "$py" "$(cygpath -w "$URTV_DIR/optimize/tv.py")" "$@"; }
expected=$'TCL\nSmart TV Pro\nG10\n12\nAljulanda TV'
identity=$(tv 'getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.product.device; getprop ro.build.version.release; settings get global device_name' | tr -d '\r')
[[ "$identity" == "$expected" ]] || { echo 'TCL identity check failed'; exit 2; }
pkg=dev.gamelingo.tv
case "${1:-status}" in
  status)
    tv "pm path $pkg; cmd appops get $pkg SYSTEM_ALERT_WINDOW; dumpsys activity services $pkg | grep -E 'ServiceRecord|isForeground'; dumpsys window windows | grep -E 'mCurrentFocus|GameLingo subtitle' | head -12"
    ;;
  install|update)
    file=${2:?Supply the absolute path to the GameLingo test APK}
    existing=$(tv "pm path $pkg" | tr -d '\r')
    if [[ "$1" == "install" && -n "$existing" ]]; then echo 'GameLingo already installed'; exit 3; fi
    if [[ "$1" == "update" && -z "$existing" ]]; then echo 'Expected the existing overlay test'; exit 3; fi
    tv --push-b64 "$file" /data/local/tmp/gamelingo-overlay-test.apk
    result=$(tv 'pm install -r /data/local/tmp/gamelingo-overlay-test.apk' | tr -d '\r')
    tv 'rm -f /data/local/tmp/gamelingo-overlay-test.apk'
    echo "$result"; [[ "$result" == *Success* ]]
    if [[ "$1" == "install" ]]; then tv "cmd appops set $pkg SYSTEM_ALERT_WINDOW allow"; fi
    tv "cmd appops get $pkg SYSTEM_ALERT_WINDOW"
    tv "am start -W -n $pkg/.MainActivity"
    ;;
  *) echo 'Usage: tcl-test.sh status | install APK'; exit 2;;
esac

