#!/usr/bin/env bash
# Capture Vitals intent-driven paywall screenshots (trial sheet + yearly paywall per gate).
set -euo pipefail

OUTPUT_ROOT="${HOME}/Desktop/paywall-screenshots/vitals/intents"
DERIVED_ROOT="${TMPDIR:-/tmp}/paywall-screenshot-dd/vitals-intents"
BUNDLE="com.jackwallner.vitals"
REPO="${HOME}/vitals"
DEVICES=("iPhone 16e" "iPhone 17")

# Settings toggles + History + Body Profile gates
GATES=(
  net-deficit
  active-resting
  tdee
  projections
  streaks
  weekly-recap
  deep-trends
  custom-range
  body-profile
)

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

for DEVICE_NAME in "${DEVICES[@]}"; do
  DEVICE_SLUG=$(slugify_device "$DEVICE_NAME")
  echo "=== intents @ $DEVICE_NAME ==="
  UDID=$(boot_sim "$DEVICE_NAME")
  DD="${DERIVED_ROOT}/${DEVICE_SLUG}"
  cd "$REPO"
  xcodegen generate >/dev/null 2>&1 || true
  xcodebuild -scheme Vitals -configuration Debug \
    -destination "platform=iOS Simulator,id=${UDID}" \
    -derivedDataPath "$DD" build CODE_SIGNING_ALLOWED=NO >/dev/null
  APP=$(find "$DD" -path '*/Build/Products/Debug-iphonesimulator/Vitals.app' -print -quit)
  xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP"

  for gate in "${GATES[@]}"; do
    for plan in trial yearly; do
      OUT_DIR="${OUTPUT_ROOT}/${DEVICE_SLUG}"
      mkdir -p "$OUT_DIR"
      OUT_FILE="${OUT_DIR}/${plan}-${gate}.png"
      SNAP="${plan}-${gate}"
      xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
      xcrun simctl launch "$UDID" "$BUNDLE" -PaywallSnapshot "$SNAP" >/dev/null
      sleep 6
      xcrun simctl io "$UDID" screenshot "$OUT_FILE"
      echo "  saved $OUT_FILE"
    done
  done
done

echo "Done: $OUTPUT_ROOT"
