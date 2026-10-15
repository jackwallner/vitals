#!/bin/bash
# Run the Android debug + instrumentation APKs on the temporary test AVD on the MacBook Pro.
# Never boots an emulator locally. Usage: scripts/android-pro.sh install | test [class] | shot <out.png> | adb <args...>
set -euo pipefail
HOST=jackwallner@192.168.4.25
SERIAL=${VITALS_ANDROID_SERIAL:-emulator-5562}
ADB=/Users/jackwallner/Library/Android/sdk/platform-tools/adb
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/android/app/build/outputs/apk"
REMOTE=/tmp/vitals-android-test
ssh_pro() { ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=yes "$HOST" "$@"; }
cmd=${1:-}; shift || true
case "$cmd" in
  install)
    ssh_pro "mkdir -p $REMOTE"
    scp -q -o BatchMode=yes -o StrictHostKeyChecking=yes "$OUT/debug/app-debug.apk" "$OUT/androidTest/debug/app-debug-androidTest.apk" "$HOST:$REMOTE/"
    ssh_pro "$ADB -s $SERIAL install -r -t $REMOTE/app-debug.apk && $ADB -s $SERIAL install -r -t $REMOTE/app-debug-androidTest.apk"
    ;;
  test)
    filter=${1:-}
    extra=""
    [ -n "$filter" ] && extra="-e class $filter"
    ssh_pro "$ADB -s $SERIAL shell am instrument -w -r $extra com.jackwallner.vitals.test/androidx.test.runner.AndroidJUnitRunner"
    ;;
  shot)
    ssh_pro "$ADB -s $SERIAL exec-out screencap -p" > "$1"
    ;;
  adb)
    ssh_pro "$ADB -s $SERIAL $*"
    ;;
  *) echo "usage: $0 install|test [class]|shot <out.png>|adb <args>" >&2; exit 2 ;;
esac
