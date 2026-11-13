#!/usr/bin/env bash
# Capture iPad screens on a throwaway 13-inch iPad simulator (2064x2752
# portrait), so the shared pool is never touched.
#
#   scripts/capture-ipad.sh <out-dir> [scene ...]
#
# Every scene is shot in portrait and landscape. `IPadCaptureUITests` rotates
# the device (only XCTest can, headless) and waits while this script takes the
# frame with `simctl io`. Needs a Debug build: screenshot scenes and fixtures
# are DEBUG-only. `ONLY=portrait|landscape` shoots one orientation,
# `APPEARANCE=dark` shoots dark, `DD=<dir>` reuses a DerivedData folder.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$1"; shift
SCENES=("$@")
[ ${#SCENES[@]} -gt 0 ] || SCENES=(dashboard history premium onboarding settings)
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
SYNC="$OUT/.sync"; rm -rf "$SYNC"; mkdir -p "$SYNC"
DD="${DD:-$OUT/.dd}"
NAME="vitals-ipad-$$"
TYPE="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-16GB"

JOBS=""
for scene in "${SCENES[@]}"; do
  for orient in portrait landscape; do
    [ -z "${ONLY:-}" ] || [ "$ONLY" = "$orient" ] || continue
    JOBS+="${JOBS:+,}$scene:$orient"
  done
done

UDID=""
for RUNTIME in $(xcrun simctl list runtimes -j | python3 -c "
import json,sys
rts=[r for r in json.load(sys.stdin)['runtimes'] if r['isAvailable'] and r['platform']=='iOS']
for r in sorted(rts, key=lambda r: [int(x) for x in r['version'].split('.')], reverse=True): print(r['identifier'])
"); do
  if UDID="$(xcrun simctl create "$NAME" "$TYPE" "$RUNTIME" 2>/dev/null)"; then break; fi
  UDID=""
done
[ -n "$UDID" ] || { echo "no runtime accepts $TYPE" >&2; exit 1; }
XB=""
trap '[ -z "$XB" ] || kill "$XB" 2>/dev/null || true; xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance "${APPEARANCE:-light}"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true

TEST_RUNNER_IPAD_JOBS="$JOBS" TEST_RUNNER_IPAD_SYNC="$SYNC" \
  xcodebuild test -project Vitals.xcodeproj -scheme VitalsUITests -destination "id=$UDID" \
  -derivedDataPath "$DD" -only-testing:VitalsUITests/IPadCaptureUITests/testCapture \
  CODE_SIGNING_ALLOWED=NO >"$OUT/xcodebuild.log" 2>&1 &
XB=$!

IFS=',' read -ra LIST <<<"$JOBS"
for job in "${LIST[@]}"; do
  name="${job/:/-}"
  until [ -f "$SYNC/$name.ready" ]; do
    kill -0 "$XB" 2>/dev/null || { echo "xcodebuild ended early, see $OUT/xcodebuild.log" >&2; exit 1; }
    sleep 2
  done
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
  touch "$SYNC/$name.done"
  echo "$OUT/$name.png"
done
wait "$XB" || true
