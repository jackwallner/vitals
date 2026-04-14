#!/usr/bin/env bash
# Optional: upload a built IPA using App Store Connect API (JWT + AuthKey_*.p8).
# Prefer ./upload-testflight.sh (xcodebuild + AppStoreUploadOptions) when you use Xcode locally.
#
#   export ASC_API_KEY_ID="..."
#   export ASC_API_ISSUER_ID="..."
#   mkdir -p ~/.appstoreconnect/private_keys && mv AuthKey_*.p8 ~/.appstoreconnect/private_keys/
#   ./scripts/upload-testflight-api.sh [path/to/app.ipa]

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPA="${1:-}"

if [[ -z "$IPA" || ! -f "$IPA" ]]; then
  IPA="$(find "$ROOT/build" -name '*.ipa' -print -quit 2>/dev/null || true)"
fi

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_API_ISSUER_ID:-}" ]]; then
  echo "error: set ASC_API_KEY_ID and ASC_API_ISSUER_ID" >&2
  exit 1
fi
if [[ -z "$IPA" || ! -f "$IPA" ]]; then
  echo "error: IPA not found. Pass path as arg or build/export an .ipa first." >&2
  exit 1
fi

xcrun iTMSTransporter \
  -m upload \
  -apiKey "$ASC_API_KEY_ID" \
  -apiIssuer "$ASC_API_ISSUER_ID" \
  -assetFile "$IPA" \
  -distribution AppStore \
  -v informational
