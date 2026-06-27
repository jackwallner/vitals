#!/usr/bin/env bash
# Capture paywall screenshots for every portfolio app across multiple iPhone sizes.
# Requires DEBUG builds with PaywallScreenshotHarness wired into each app.
set -euo pipefail

OUTPUT_ROOT="${HOME}/Desktop/paywall-screenshots"
DERIVED_ROOT="${TMPDIR:-/tmp}/paywall-screenshot-dd"
LOG_ROOT="${OUTPUT_ROOT}/_logs"
MODES=(trial monthly yearly lifetime)
DEVICES=("iPhone 16e" "iPhone 17" "iPhone 17 Pro Max")

# slug|repo|scheme|bundle_id|storekit_filename
APPS=(
  "vitals|${HOME}/vitals|Vitals|com.jackwallner.vitals|Vitals.storekit"
  "posture|${HOME}/posture|Posture|com.jackwallner.posture|Posture.storekit"
  "bond|${HOME}/bond|Bond|com.jackwallner.bond|Bond.storekit"
  "fitness-streaks|${HOME}/fitness-streaks|FitnessStreaks|com.jackwallner.streaks|FitnessStreaks.storekit"
  "sober|${HOME}/sober|Sober|com.jackwallner.sober|Sober.storekit"
  "nicfree|${HOME}/nicfree|Sober|com.jackwallner.quitzyn|Sober.storekit"
  "simpleglp|${HOME}/simpleglp|SimpleGLP|com.jackwallner.glp|SimpleGLP.storekit"
  "gist|${HOME}/sports|Sideline|com.jackwallner.sports|Sideline.storekit"
  "baseball|${HOME}/baseball|StatScout|com.jackwallner.baseball|StatScout.storekit"
  "headaches|${HOME}/headaches|HeadacheLogger|com.jackwallner.headachelogger|HeadacheLogger.storekit"
)

mkdir -p "$OUTPUT_ROOT" "$LOG_ROOT"
README="${OUTPUT_ROOT}/README.md"
cat > "$README" <<'EOF'
# Portfolio paywall screenshots

Captured via `vitals/scripts/capture-portfolio-paywall-screenshots.sh`.

## Modes
- **trial** — half-sheet trial pitch (`.fraction(0.68)` where the app has a trial sheet)
- **monthly** — full paywall, monthly plan selected
- **yearly** — full paywall, yearly plan selected
- **lifetime** — full paywall, lifetime plan selected

## Devices
- `iphone-16e` — compact (small phone class)
- `iphone-17` — standard
- `iphone-17-pro-max` — large

## Also worth reviewing manually
- Trial-ineligible subscriber (no “Start Free Trial” CTA)
- Loading / couldn’t-load-plans empty states (3.1.2 legal links)
- Intent-driven paywall (feature focus) per app
EOF

slugify_device() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

boot_sim() {
  local device_name="$1"
  local udid
  udid=$(xcrun simctl list devices available | grep "$device_name (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
  if [[ -z "$udid" ]]; then
    echo "ERROR: Simulator not found: $device_name" >&2
    exit 1
  fi
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  # Headless — simctl can install, launch, and screenshot without opening Simulator.app
  echo "$udid"
}

build_app() {
  local repo="$1" scheme="$2" slug="$3" device_slug="$4" udid="$5"
  local dd="${DERIVED_ROOT}/${slug}-${device_slug}"
  local log="${LOG_ROOT}/${slug}-${device_slug}.log"

  cd "$repo"
  if [[ -f project.yml ]]; then xcodegen generate >/dev/null; fi

  if ! xcodebuild \
    -scheme "$scheme" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=${udid}" \
    -derivedDataPath "$dd" \
    build \
    CODE_SIGNING_ALLOWED=NO \
    >"$log" 2>&1; then
    echo "WARN: build failed for $slug ($device_slug) — see $log" >&2
    rg "error:" "$log" | tail -5 >&2 || tail -20 "$log" >&2
    return 1
  fi

  find "$dd" -path "*/Build/Products/Debug-iphonesimulator/${scheme}.app" -print -quit
}

for DEVICE_NAME in "${DEVICES[@]}"; do
  DEVICE_SLUG=$(slugify_device "$DEVICE_NAME")
  echo "=== Device: $DEVICE_NAME ==="
  UDID=$(boot_sim "$DEVICE_NAME")

  for entry in "${APPS[@]}"; do
    IFS='|' read -r slug repo scheme bundle _storekit <<< "$entry"
    echo "--- $slug ---"
    APP_PATH=$(build_app "$repo" "$scheme" "$slug" "$DEVICE_SLUG" "$UDID" || true)
    if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
      echo "WARN: no .app for $slug on $DEVICE_SLUG" >&2
      continue
    fi

    xcrun simctl uninstall "$UDID" "$bundle" >/dev/null 2>&1 || true
    xcrun simctl install "$UDID" "$APP_PATH"

    for mode in "${MODES[@]}"; do
      OUT_DIR="${OUTPUT_ROOT}/${slug}/${DEVICE_SLUG}"
      mkdir -p "$OUT_DIR"
      OUT_FILE="${OUT_DIR}/${mode}.png"

      xcrun simctl terminate "$UDID" "$bundle" >/dev/null 2>&1 || true
      xcrun simctl launch "$UDID" "$bundle" -PaywallSnapshot "$mode" >/dev/null
      sleep 6
      xcrun simctl io "$UDID" screenshot "$OUT_FILE"
      echo "  saved $OUT_FILE"
    done
  done
done

echo "Done. Screenshots in $OUTPUT_ROOT"
