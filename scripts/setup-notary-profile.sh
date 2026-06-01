#!/usr/bin/env bash
# Store notarytool credentials in Keychain (AC_NOTARY) using App Store Connect API key.
set -euo pipefail

KEY="${NOTARY_API_KEY_PATH:-$HOME/Downloads/Sonstiges/AuthKey_G96FPL6C25.p8}"
KEY_ID="${NOTARY_KEY_ID:-G96FPL6C25}"
ISSUER="${NOTARY_ISSUER_ID:-980e2f89-397e-48b2-8880-67beae9b27fe}"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

if [[ ! -f "$KEY" ]]; then
  echo "error: API key not found at $KEY" >&2
  echo "Download AuthKey_*.p8 from App Store Connect → Users and Access → Integrations → API" >&2
  exit 1
fi

xcrun notarytool store-credentials "$PROFILE" \
  --key "$KEY" \
  --key-id "$KEY_ID" \
  --issuer "$ISSUER"

echo "Profile \"$PROFILE\" is ready. Run: bash scripts/notarize-hal-driver.sh"
