#!/usr/bin/env bash
# Create CSR + private key for Developer ID Installer (upload to developer.apple.com).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${APM44_CSR_DIR:-$ROOT/build/signing/cert-request}"
EMAIL="${APM44_CSR_EMAIL:-$(git -C "$ROOT" config user.email 2>/dev/null || true)}"
CN="${APM44_CSR_CN:-$(git -C "$ROOT" config user.name 2>/dev/null || true)}"
COUNTRY="${APM44_CSR_COUNTRY:-}"

mkdir -p "$DIR"
if [[ -z "$EMAIL" ]]; then
  echo "error: set APM44_CSR_EMAIL or git config user.email" >&2
  exit 1
fi
if [[ -z "$CN" ]]; then
  echo "error: set APM44_CSR_CN or git config user.name" >&2
  exit 1
fi

openssl genrsa -out "$DIR/installer.key" 2048
SUBJECT="/emailAddress=${EMAIL}/CN=${CN}"
if [[ -n "$COUNTRY" ]]; then
  SUBJECT="${SUBJECT}/C=${COUNTRY}"
fi
openssl req -new -key "$DIR/installer.key" \
  -out "$DIR/DeveloperIDInstaller.certSigningRequest" \
  -subj "$SUBJECT"

echo "CSR ready: $DIR/DeveloperIDInstaller.certSigningRequest"
echo "Private key (keep secret): $DIR/installer.key"
echo ""
echo "Upload the .certSigningRequest at:"
echo "  https://developer.apple.com/account/resources/certificates/add"
echo "  → Developer ID Installer → Continue → choose file → Continue"
