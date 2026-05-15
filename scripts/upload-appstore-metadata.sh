#!/bin/bash
# Push screenshots + metadata to App Store Connect via fastlane (no binary upload).
# Reads ASC API key from env or ~/.baseball_credentials.
# Project's bundle ID, metadata, and screenshots live in ./fastlane/
set -e
cd "$(dirname "$0")/.."

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDS="$HOME/.baseball_credentials"
  [[ -f "$CREDS" ]] && source "$CREDS"
fi

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  echo "error: ASC_API_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH must be set" >&2
  echo "       see ~/.baseball_credentials" >&2
  exit 1
fi

if [[ ! -d fastlane ]]; then
  echo "error: fastlane/ not configured in $(pwd)" >&2
  echo "       reference: ~/baseball/fastlane (Appfile, Fastfile, metadata/, screenshots/)" >&2
  exit 1
fi

if [[ -f Gemfile ]]; then
  exec bundle exec fastlane upload_metadata "$@"
elif command -v fastlane >/dev/null; then
  exec fastlane upload_metadata "$@"
else
  echo "error: fastlane not installed (brew install fastlane)" >&2
  exit 1
fi
