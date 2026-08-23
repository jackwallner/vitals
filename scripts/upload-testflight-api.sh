#!/usr/bin/env bash
# Optional: upload a built IPA using App Store Connect API (JWT + AuthKey_*.p8).
# Prefer ./upload-testflight.sh (xcodebuild + AppStoreUploadOptions) when you use Xcode locally.
#
#   export ASC_API_KEY_ID="..."
#   export ASC_API_ISSUER_ID="..."
#   mkdir -p ~/.appstoreconnect/private_keys && mv AuthKey_*.p8 ~/.appstoreconnect/private_keys/
#   ./scripts/upload-testflight-api.sh [path/to/app.ipa]
#
# The IPA argument is checked against project.yml before anything is uploaded.
# It used to default to `find build -name '*.ipa' -print -quit`, which returns
# whichever IPA the filesystem happened to name first. On this repo that was a
# 1.1.0 (build 8) artifact left in build/export, so a bare invocation would
# cheerfully ship a version from months ago. Set ALLOW_VERSION_MISMATCH=1 to
# upload something that does not match the working tree on purpose.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPA="${1:-}"

if [[ -z "$IPA" ]]; then
  # Newest, not first-found, and still verified below.
  IPA="$(find "$ROOT/build" -name '*.ipa' -type f -print0 2>/dev/null \
         | xargs -0 ls -t 2>/dev/null | head -1 || true)"
  [[ -n "$IPA" ]] && echo "note: no IPA given, using newest under build/: $IPA"
fi

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_API_ISSUER_ID:-}" ]]; then
  echo "error: set ASC_API_KEY_ID and ASC_API_ISSUER_ID" >&2
  exit 1
fi
if [[ -z "$IPA" || ! -f "$IPA" ]]; then
  echo "error: IPA not found. Pass path as arg or build/export an .ipa first." >&2
  exit 1
fi

# --- Verify the artifact is the one this working tree describes -------------
want_version="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' "$ROOT/project.yml")"
want_build="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' "$ROOT/project.yml")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if ! unzip -q -o "$IPA" 'Payload/*.app/Info.plist' -d "$tmp" 2>/dev/null; then
  echo "error: could not read Info.plist out of $IPA (is it a valid IPA?)" >&2
  exit 1
fi
plist="$(find "$tmp/Payload" -maxdepth 2 -name Info.plist -print -quit)"
if [[ -z "$plist" ]]; then
  echo "error: no app Info.plist inside $IPA" >&2
  exit 1
fi
got_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo '?')"
got_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo '?')"

echo "IPA:        $IPA"
echo "  contains: $got_version ($got_build)"
echo "  expected: $want_version ($want_build)"

if [[ "$got_version" != "$want_version" || "$got_build" != "$want_build" ]]; then
  if [[ "${ALLOW_VERSION_MISMATCH:-0}" == "1" ]]; then
    echo "warning: version mismatch, uploading anyway (ALLOW_VERSION_MISMATCH=1)" >&2
  else
    echo "error: this IPA is not the current build. Re-export, pass the right path," >&2
    echo "       or set ALLOW_VERSION_MISMATCH=1 if the mismatch is intentional." >&2
    exit 1
  fi
fi

xcrun iTMSTransporter \
  -m upload \
  -apiKey "$ASC_API_KEY_ID" \
  -apiIssuer "$ASC_API_ISSUER_ID" \
  -assetFile "$IPA" \
  -distribution AppStore \
  -v informational
