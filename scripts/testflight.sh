#!/usr/bin/env bash
# One-shot: regenerate project, Release archive, upload to TestFlight (local Xcode account).
# Uses scripts/upload-testflight.sh (AppStoreUploadOptions.plist + destination=upload).
#
#   ./scripts/testflight.sh
#
# If you already have build/Vitals.xcarchive:
#   ./scripts/upload-testflight.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> xcodegen"
command -v xcodegen >/dev/null && xcodegen generate || { echo "Install xcodegen: brew install xcodegen" >&2; exit 1; }

ARCHIVE="$ROOT/build/Vitals.xcarchive"
rm -rf "$ARCHIVE"

echo "==> Archive (Release)"
xcodebuild -project Vitals.xcodeproj \
  -scheme Vitals \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  archive

exec "$ROOT/scripts/upload-testflight.sh" "$ARCHIVE"
