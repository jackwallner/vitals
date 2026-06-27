#!/usr/bin/env bash
# Capture paywall screenshots for ONE app across iPhone sizes (headless sim).
# Usage: capture-paywall-app.sh <slug>
set -euo pipefail

SLUG="${1:?usage: capture-paywall-app.sh <slug>}"
OUTPUT_ROOT="${HOME}/Desktop/paywall-screenshots"
DERIVED_ROOT="${TMPDIR:-/tmp}/paywall-screenshot-dd"
LOG_ROOT="${OUTPUT_ROOT}/_logs"
MODES=(trial monthly yearly lifetime)
DEVICES=("iPhone 16e" "iPhone 17" "iPhone 17 Pro Max")

lookup_app() {
  case "$1" in
    vitals)         echo "${HOME}/vitals|Vitals|com.jackwallner.vitals" ;;
    posture)        echo "${HOME}/posture|Posture|com.jackwallner.posture" ;;
    bond)           echo "${HOME}/bond|Bond|com.jackwallner.bond" ;;
    fitness-streaks) echo "${HOME}/fitness-streaks|FitnessStreaks|com.jackwallner.streaks" ;;
    sober)          echo "${HOME}/sober|Sober|com.jackwallner.sober" ;;
    nicfree)        echo "${HOME}/nicfree|Sober|com.jackwallner.quitzyn" ;;
    simpleglp)      echo "${HOME}/simpleglp|SimpleGLP|com.jackwallner.glp" ;;
    gist)           echo "${HOME}/sports|Sideline|com.jackwallner.sports" ;;
    baseball)       echo "${HOME}/baseball|StatScout|com.jackwallner.baseball" ;;
    headaches)      echo "${HOME}/headaches|HeadacheLogger|com.jackwallner.headachelogger" ;;
    *) echo "Unknown slug: $1" >&2; exit 1 ;;
  esac
}

IFS='|' read -r repo scheme bundle <<< "$(lookup_app "$SLUG")"
mkdir -p "$OUTPUT_ROOT/$SLUG" "$LOG_ROOT"

slugify_device() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

boot_sim() {
  local device_name="$1"
  local udid
  udid=$(xcrun simctl list devices available | grep "$device_name (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
  [[ -n "$udid" ]] || { echo "ERROR: Simulator not found: $device_name" >&2; exit 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  echo "$udid"
}

build_app() {
  local device_slug="$1" udid="$2"
  local dd="${DERIVED_ROOT}/${SLUG}-${device_slug}"
  local log="${LOG_ROOT}/${SLUG}-${device_slug}.log"
  cd "$repo"
  [[ -f project.yml ]] && xcodegen generate >/dev/null
  xcodebuild -scheme "$scheme" -configuration Debug \
    -destination "platform=iOS Simulator,id=${udid}" \
    -derivedDataPath "$dd" build CODE_SIGNING_ALLOWED=NO >"$log" 2>&1
  find "$dd" -path "*/Build/Products/Debug-iphonesimulator/${scheme}.app" -print -quit
}

for DEVICE_NAME in "${DEVICES[@]}"; do
  DEVICE_SLUG=$(slugify_device "$DEVICE_NAME")
  echo "=== $SLUG @ $DEVICE_NAME ==="
  UDID=$(boot_sim "$DEVICE_NAME")
  APP_PATH=$(build_app "$DEVICE_SLUG" "$UDID")
  xcrun simctl uninstall "$UDID" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP_PATH"
  for mode in "${MODES[@]}"; do
    OUT_DIR="${OUTPUT_ROOT}/${SLUG}/${DEVICE_SLUG}"
    mkdir -p "$OUT_DIR"
    OUT_FILE="${OUT_DIR}/${mode}.png"
    xcrun simctl terminate "$UDID" "$bundle" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$bundle" -PaywallSnapshot "$mode" >/dev/null
    sleep 6
    xcrun simctl io "$UDID" screenshot "$OUT_FILE"
    echo "  saved $OUT_FILE"
  done
done

echo "Done: $OUTPUT_ROOT/$SLUG"
