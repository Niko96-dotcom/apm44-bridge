#!/usr/bin/env bash
# Store notarytool credentials in Keychain using an App Store Connect API key.
set -euo pipefail

KEY="${NOTARY_API_KEY_PATH:-}"
KEY_ID="${NOTARY_KEY_ID:-}"
ISSUER="${NOTARY_ISSUER_ID:-}"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: setup-notary-profile.sh [--help]

Required environment:
  NOTARY_API_KEY_PATH   path to AuthKey_<KEY_ID>.p8
  NOTARY_KEY_ID         App Store Connect API key ID
  NOTARY_ISSUER_ID      App Store Connect issuer UUID

Optional environment:
  NOTARY_PROFILE        keychain profile name (default AC_NOTARY)
EOF
  exit 0
fi

if [[ -z "$KEY" || -z "$KEY_ID" || -z "$ISSUER" ]]; then
  echo "error: set NOTARY_API_KEY_PATH, NOTARY_KEY_ID, and NOTARY_ISSUER_ID" >&2
  echo "hint: download AuthKey_<KEY_ID>.p8 from App Store Connect -> Users and Access -> Integrations -> API" >&2
  exit 1
fi

if [[ ! -f "$KEY" ]]; then
  echo "error: API key not found at $KEY" >&2
  echo "hint: download AuthKey_<KEY_ID>.p8 from App Store Connect -> Users and Access -> Integrations -> API" >&2
  exit 1
fi

xcrun notarytool store-credentials "$PROFILE" \
  --key "$KEY" \
  --key-id "$KEY_ID" \
  --issuer "$ISSUER"

echo "Profile \"$PROFILE\" is ready. Run: bash scripts/notarize-hal-driver.sh"
