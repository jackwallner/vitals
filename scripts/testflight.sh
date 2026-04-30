#!/usr/bin/env bash
# One-shot: bump build, regenerate project, Release archive, upload to TestFlight.
# Uses scripts/upload-testflight.sh (AppStoreUploadOptions.plist + destination=upload).
#
#   ./scripts/testflight.sh
#
# If you already have build/Vitals.xcarchive:
#   ./scripts/upload-testflight.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Auto-bump build number in project.yml
PROJECT_YML="$ROOT/project.yml"
if [[ -f "$PROJECT_YML" ]]; then
    CURRENT_BUILD=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | sed -E 's/.*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9]+)"?.*/\1/')
    if [[ -n "$CURRENT_BUILD" && "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
        NEW_BUILD=$((CURRENT_BUILD + 1))
        echo "==> Bump build $CURRENT_BUILD -> $NEW_BUILD"
        sed -i '' -E "s/(CURRENT_PROJECT_VERSION:[[:space:]]*\")$CURRENT_BUILD/\1$NEW_BUILD/" "$PROJECT_YML"
        git add project.yml
        git commit -m "Bump build $CURRENT_BUILD -> $NEW_BUILD" || true
        git push origin main || true
    else
        echo "Warning: Could not parse CURRENT_PROJECT_VERSION from project.yml" >&2
    fi
else
    echo "Warning: project.yml not found" >&2
fi

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
