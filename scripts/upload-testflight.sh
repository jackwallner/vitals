#!/usr/bin/env bash
# Upload to TestFlight via xcodebuild -exportArchive with AppStoreUploadOptions.plist
# (destination=upload, method=app-store-connect) and -allowProvisioningUpdates,
# so Xcode uses your local App Store Connect / Apple ID session (no JWT in repo).
#
# Same pattern as ../headaches/scripts/upload-testflight.sh (that script references this flow).
#
# Prerequisites: Xcode signed in (Xcode → Settings → Accounts) with team YXG4MP6W39.
#
# Usage (from vitals/):
#   ./scripts/upload-testflight.sh [path/to/Vitals.xcarchive]
#
# Default archive: ./build/Vitals.xcarchive
#
# Alternative (API key / CI): see scripts/upload-testflight-api.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:-$ROOT/build/Vitals.xcarchive}"
STAGING="$ROOT/build/upload-staging"
PLIST="$ROOT/AppStoreUploadOptions.plist"

if [[ ! -d "$ARCHIVE" ]]; then
  echo "error: archive not found: $ARCHIVE" >&2
  echo "Create one first, e.g.:" >&2
  cat >&2 <<'EOF'
  cd vitals && xcodegen generate && xcodebuild -project Vitals.xcodeproj \
    -scheme Vitals -configuration Release -destination 'generic/platform=iOS' \
    -archivePath "$(pwd)/build/Vitals.xcarchive" -allowProvisioningUpdates archive
EOF
  exit 1
fi

if [[ ! -f "$PLIST" ]]; then
  echo "error: missing $PLIST" >&2
  exit 1
fi

mkdir -p "$STAGING"
echo "Uploading archive via App Store Connect (local Xcode session)..."
echo "  archive: $ARCHIVE"
echo "  plist:   $PLIST"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$STAGING" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates

echo "If upload succeeded, check App Store Connect → TestFlight for “Processing”."
