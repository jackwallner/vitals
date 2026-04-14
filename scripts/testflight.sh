#!/usr/bin/env bash
# Archive the iOS app and export an App Store IPA for TestFlight / App Store Connect.
# Usage: from repo root: ./scripts/testflight.sh
#
# Optional upload (pick one):
#   1) Open Transporter.app and drag build/export/Vitals.ipa
#   2) API key env vars (see https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api):
#        export APP_STORE_CONNECT_API_KEY_ID=...
#        export APP_STORE_CONNECT_API_ISSUER_ID=...
#        export APP_STORE_CONNECT_API_KEY_PATH="$HOME/AuthKey_XXXXX.p8"
#      Then this script runs: xcrun altool --upload-app ...

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> xcodegen"
command -v xcodegen >/dev/null && xcodegen generate || { echo "Install xcodegen: brew install xcodegen"; exit 1; }

SCHEME="Vitals"
ARCHIVE="$ROOT/build/Vitals.xcarchive"
EXPORT_DIR="$ROOT/build/export"
EXPORT_PLIST="$ROOT/ExportOptions-AppStore.plist"

rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$ROOT/build" "$EXPORT_DIR"

echo "==> Archive (Release, generic iOS)"
xcodebuild \
  -project Vitals.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  archive \
  CODE_SIGN_STYLE=Automatic

echo "==> Export IPA"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

IPA="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "$IPA" || ! -f "$IPA" ]]; then
  echo "Export failed: no .ipa in $EXPORT_DIR" >&2
  exit 1
fi

echo "==> IPA: $IPA"

if [[ -n "${APP_STORE_CONNECT_API_KEY_ID:-}" && -n "${APP_STORE_CONNECT_API_ISSUER_ID:-}" && -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
  echo "==> Upload to App Store Connect (TestFlight processing)"
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
    --apiIssuer "$APP_STORE_CONNECT_API_ISSUER_ID" \
    --apiKeyPath "$APP_STORE_CONNECT_API_KEY_PATH"
  echo "==> Upload submitted. Check App Store Connect → TestFlight for build processing."
else
  echo "==> Upload: set APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_ISSUER_ID, APP_STORE_CONNECT_API_KEY_PATH to upload from CLI,"
  echo "    or upload $IPA with Transporter."
fi
