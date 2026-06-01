#!/usr/bin/env bash
# Install Developer ID Installer .cer + private key + Apple G2 intermediate (required for productsign).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CER="${1:-}"
KEY="${APM44_INSTALLER_KEY:-$ROOT/build/signing/cert-request/installer.key}"
DIR="$(dirname "$KEY")"
G2_CA_URL="https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer"
G2_CA="${APM44_DEVID_G2_CA:-/tmp/DeveloperIDG2CA.cer}"
KC="${APM44_INSTALLER_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
P12_PASS="${APM44_INSTALLER_P12_PASS:-apm44}"

if [[ -z "$CER" || ! -f "$CER" ]]; then
  echo "Usage: install-installer-cert.sh ~/Downloads/developerID_installer.cer" >&2
  exit 1
fi

if [[ ! -f "$KEY" ]]; then
  echo "error: private key not found at $KEY (run scripts/create-installer-csr.sh on this Mac)" >&2
  exit 1
fi

curl -fsSL -o "$G2_CA" "$G2_CA_URL"
security import "$G2_CA" -k "$KC" 2>/dev/null || true

PEM="$DIR/installer.pem"
P12="$DIR/installer-for-keychain.p12"
openssl x509 -inform DER -in "$CER" -out "$PEM"
openssl pkcs12 -export -legacy -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg SHA1 \
  -out "$P12" -inkey "$KEY" -in "$PEM" \
  -passout "pass:$P12_PASS" -name "Developer ID Installer: Nikolay Mohr (4H5447ZWS3)"

security import "$P12" -k "$KC" -P "$P12_PASS" -A \
  -T /usr/bin/productsign -T /usr/bin/codesign -f pkcs12 2>/dev/null || \
  security import "$P12" -k "$KC" -P "$P12_PASS" -T /usr/bin/productsign -T /usr/bin/codesign -f pkcs12

security unlock-keychain -p "" "$KC" 2>/dev/null || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KC" 2>/dev/null || true

echo ""
echo "Installed. Verify:"
if security find-identity -v -p basic 2>/dev/null | grep -q "Developer ID Installer"; then
  security find-identity -v -p basic | grep "Developer ID Installer"
else
  echo "  (If empty, open Keychain Access and confirm Developer ID Installer + private key are paired)"
fi
echo ""
echo "Next: bash scripts/build-release-pkg.sh && bash scripts/notarize-release-pkg.sh"
