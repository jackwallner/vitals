#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

IPHONE_DEVICE="${IPHONE_DEVICE:-iPhone 17 Pro Max}"
WATCH_DEVICE="${WATCH_DEVICE:-Apple Watch Ultra 3 (49mm)}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-$ROOT_DIR/screenshots}"

IPHONE_UDID="$(xcrun simctl list devices available | awk -v device="$IPHONE_DEVICE" '$0 ~ device { gsub(/[()]/, "", $NF); print $NF; exit }')"
WATCH_UDID="$(xcrun simctl list devices available | awk -v device="$WATCH_DEVICE" '$0 ~ device { gsub(/[()]/, "", $NF); print $NF; exit }')"

if [[ -z "$IPHONE_UDID" ]]; then
  echo "Could not find iPhone simulator: $IPHONE_DEVICE" >&2
  exit 1
fi

if [[ -z "$WATCH_UDID" ]]; then
  echo "Could not find Apple Watch simulator: $WATCH_DEVICE" >&2
  exit 1
fi

mkdir -p "$SCREENSHOT_DIR"

echo "Generating Xcode project..."
xcodegen generate >/dev/null

echo "Building iPhone simulator app..."
xcodebuild \
  -scheme "Vitals" \
  -project "Vitals.xcodeproj" \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=$IPHONE_DEVICE" \
  -derivedDataPath "build/DerivedData-iOS" \
  build >/dev/null

echo "Capturing iPhone screenshots..."
xcrun simctl boot "$IPHONE_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$IPHONE_UDID" -b >/dev/null
xcrun simctl install "$IPHONE_UDID" "build/DerivedData-iOS/Build/Products/Debug-iphonesimulator/Vitals.app" >/dev/null

capture_iphone() {
  local scene="$1"
  local filename="$2"
  SIMCTL_CHILD_VITALS_SCREENSHOT_MODE=1 \
  SIMCTL_CHILD_VITALS_SCREENSHOT_SCENE="$scene" \
    xcrun simctl launch --terminate-running-process "$IPHONE_UDID" com.jackwallner.vitals >/dev/null
  sleep 4
  xcrun simctl io "$IPHONE_UDID" screenshot "$SCREENSHOT_DIR/$filename" >/dev/null
}

capture_iphone dashboard "iphone-dashboard.png"
capture_iphone minimal "iphone-minimal.png"
capture_iphone history "iphone-history.png"
capture_iphone settings "iphone-settings.png"
capture_iphone onboarding "iphone-onboarding.png"

echo "Building Apple Watch simulator app..."
xcodebuild \
  -scheme "VitalsWatch" \
  -project "Vitals.xcodeproj" \
  -configuration Debug \
  -destination "platform=watchOS Simulator,name=$WATCH_DEVICE" \
  -derivedDataPath "build/DerivedData-Watch" \
  build >/dev/null

echo "Capturing Apple Watch screenshots..."
xcrun simctl boot "$WATCH_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$WATCH_UDID" -b >/dev/null
xcrun simctl install "$WATCH_UDID" "build/DerivedData-Watch/Build/Products/Debug-watchsimulator/VitalsWatch.app" >/dev/null

capture_watch() {
  local scene="$1"
  local filename="$2"
  SIMCTL_CHILD_VITALS_SCREENSHOT_MODE=1 \
  SIMCTL_CHILD_VITALS_SCREENSHOT_SCENE="$scene" \
    xcrun simctl launch --terminate-running-process "$WATCH_UDID" com.jackwallner.vitals.watch >/dev/null
  sleep 4
  xcrun simctl io "$WATCH_UDID" screenshot "$SCREENSHOT_DIR/$filename" >/dev/null
}

capture_watch watchToday "watch-today.png"
capture_watch watchBreakdown "watch-breakdown.png"
capture_watch watchHelp "watch-help.png"

echo "Screenshots written to $SCREENSHOT_DIR"
