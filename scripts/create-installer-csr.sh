#!/usr/bin/env bash
# Create CSR + private key for Developer ID Installer (upload to developer.apple.com).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${APM44_CSR_DIR:-$ROOT/build/signing/cert-request}"
EMAIL="${APM44_CSR_EMAIL:-$(git -C "$ROOT" config user.email 2>/dev/null || true)}"
CN="${APM44_CSR_CN:-Nikolay Mohr}"

mkdir -p "$DIR"
if [[ -z "$EMAIL" ]]; then
  echo "error: set APM44_CSR_EMAIL or git config user.email" >&2
  exit 1
fi

openssl genrsa -out "$DIR/installer.key" 2048
openssl req -new -key "$DIR/installer.key" \
  -out "$DIR/DeveloperIDInstaller.certSigningRequest" \
  -subj "/emailAddress=${EMAIL}/CN=${CN}/C=DE"

echo "CSR ready: $DIR/DeveloperIDInstaller.certSigningRequest"
echo "Private key (keep secret): $DIR/installer.key"
echo ""
echo "Upload the .certSigningRequest at:"
echo "  https://developer.apple.com/account/resources/certificates/add"
echo "  → Developer ID Installer → Continue → choose file → Continue"
