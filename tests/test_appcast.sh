#!/usr/bin/env bash
# Credential-free regression tests for Sparkle package appcast validation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

grep -Fq '<key>SUFeedURL</key>' "$ROOT/App/APM44Bridge/Info.plist"
grep -Fq '<key>SUPublicEDKey</key>' "$ROOT/App/APM44Bridge/Info.plist"
grep -Fq '<key>SUEnableAutomaticChecks</key>' "$ROOT/App/APM44Bridge/Info.plist"
grep -Fq '<key>SURequireSignedFeed</key>' "$ROOT/App/APM44Bridge/Info.plist"
grep -Fq '<key>SUVerifyUpdateBeforeExtraction</key>' "$ROOT/App/APM44Bridge/Info.plist"
grep -Fq 'sparkle:installationType="package"' "$ROOT/scripts/generate-appcast.sh"
grep -Fq 'sparkle:format="markdown"' "$ROOT/scripts/generate-appcast.sh"

SIGNATURE="$(python3 - <<'PY'
import base64
print(base64.b64encode(bytes(range(64))).decode())
PY
)"

SIGNER="$TMP/sign_update"
cat >"$SIGNER" <<'SIGNER'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" --verify "* ]]; then
  [[ "${APM44_FAKE_SIGN_MODE:-ok}" == "fail" ]] && exit 1
  exit 0
fi
printf 'sparkle:edSignature="%s"\n' "${APM44_FAKE_SIGNATURE:?}"
SIGNER
chmod +x "$SIGNER"

GOOD="$TMP/good.xml"
cat >"$GOOD" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>APM44 Bridge Updates</title>
    <item>
      <sparkle:version>0.12.3</sparkle:version>
      <description>APM44 Bridge 0.12.3 test notes</description>
      <enclosure url="https://github.com/Niko96-dotcom/apm44-bridge/releases/download/v0.12.3/APM44Bridge-0.12.3.pkg"
                 sparkle:edSignature="$SIGNATURE"
                 sparkle:installationType="package"
                 length="123"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

run_validation() {
  env \
    APM44_APPCAST_PATH="$1" \
    SPARKLE_SIGN_UPDATE="$SIGNER" \
    APM44_FAKE_SIGNATURE="$SIGNATURE" \
    /bin/bash "$ROOT/scripts/validate-appcast.sh" >/dev/null
}

expect_failure() {
  local path="$1"
  if env \
    APM44_APPCAST_PATH="$path" \
    SPARKLE_SIGN_UPDATE="$SIGNER" \
    APM44_FAKE_SIGNATURE="$SIGNATURE" \
    /bin/bash "$ROOT/scripts/validate-appcast.sh" >/dev/null 2>&1; then
    echo "expected appcast validation failure for $path" >&2
    exit 1
  fi
}

run_validation "$GOOD"

MALFORMED="$TMP/malformed.xml"
printf '<rss><channel>' >"$MALFORMED"
expect_failure "$MALFORMED"

UNSIGNED="$TMP/unsigned.xml"
sed 's/sparkle:edSignature="[^"]*"/sparkle:edSignature=""/' "$GOOD" >"$UNSIGNED"
expect_failure "$UNSIGNED"

BAD_SIGNATURE="$TMP/bad-signature.xml"
sed 's/sparkle:edSignature="[^"]*"/sparkle:edSignature="not-a-signature"/' "$GOOD" >"$BAD_SIGNATURE"
expect_failure "$BAD_SIGNATURE"

UNSIGNED_NOTES="$TMP/unsigned-notes.xml"
sed 's#<description>APM44 Bridge 0.12.3 test notes</description>#<sparkle:releaseNotesLink>https://example.com/notes.html</sparkle:releaseNotesLink>#' "$GOOD" >"$UNSIGNED_NOTES"
expect_failure "$UNSIGNED_NOTES"

INSECURE="$TMP/insecure.xml"
sed 's#https://github.com#http://github.com#' "$GOOD" >"$INSECURE"
expect_failure "$INSECURE"

if env \
  APM44_APPCAST_PATH="$GOOD" \
  SPARKLE_SIGN_UPDATE="$SIGNER" \
  APM44_FAKE_SIGNATURE="$SIGNATURE" \
  APM44_FAKE_SIGN_MODE=fail \
  /bin/bash "$ROOT/scripts/validate-appcast.sh" >/dev/null 2>&1; then
  echo "expected cryptographically invalid appcast to fail closed" >&2
  exit 1
fi

# The enclosure must describe the exact PKG that is uploaded and downloaded.
# This fake signs a file with the SHA-512 digest of its bytes (64 bytes, like
# Ed25519) and verifies by recomputing it, so any byte change breaks it.
PKG_SIGNER="$TMP/pkg_sign_update"
cat >"$PKG_SIGNER" <<'SIGNER'
#!/usr/bin/env bash
set -euo pipefail
digest() {
  python3 -c 'import base64, hashlib, sys; print(base64.b64encode(hashlib.sha512(open(sys.argv[1], "rb").read()).digest()).decode())' "$1"
}
case "$1" in
  -p) digest "$2" ;;
  --verify)
    # Two operands verify an update file; one operand is the signed feed.
    [[ $# -eq 2 ]] && exit 0
    [[ "$(digest "$2")" == "$3" ]] || { echo "fake: signature mismatch" >&2; exit 1; }
    ;;
  --disable-signing-warning) ;;
  *) echo "fake sign_update: unexpected arguments: $*" >&2; exit 2 ;;
esac
SIGNER
chmod +x "$PKG_SIGNER"

PKG_DIR="$TMP/pkg"
mkdir -p "$PKG_DIR"
PKG="$PKG_DIR/APM44Bridge-9.9.9.pkg"
printf 'pkg-v1' >"$PKG"
GENERATED="$TMP/generated.xml"
env -u SPARKLE_PRIVATE_KEY \
  APM44_RELEASE_PKG="$PKG" \
  APM44_APPCAST_PATH="$GENERATED" \
  APM44_RELEASE_URL="https://example.com/download/APM44Bridge-9.9.9.pkg" \
  SPARKLE_SIGN_UPDATE="$PKG_SIGNER" \
  /bin/bash "$ROOT/scripts/generate-appcast.sh" >/dev/null

# Runs the validator against the generated feed with --pkg; prints stderr.
validate_pkg() {
  env -u SPARKLE_PRIVATE_KEY \
    APM44_APPCAST_PATH="$GENERATED" \
    SPARKLE_SIGN_UPDATE="$PKG_SIGNER" \
    /bin/bash "$ROOT/scripts/validate-appcast.sh" --pkg "$1" 2>&1 >/dev/null
}

expect_pkg_failure() {
  local pkg="$1" expected="$2" output
  if output="$(validate_pkg "$pkg")"; then
    echo "expected --pkg validation to fail for $pkg" >&2
    exit 1
  fi
  [[ "$output" == *"$expected"* ]] || {
    echo "expected '$expected' from --pkg validation, got: $output" >&2
    exit 1
  }
}

# a) The PKG the feed was generated from passes.
if ! output="$(validate_pkg "$PKG")"; then
  echo "expected --pkg validation to pass for the generated PKG, got: $output" >&2
  exit 1
fi

# b) A rebuilt PKG with a different size fails on length.
LONGER="$TMP/longer/APM44Bridge-9.9.9.pkg"
mkdir -p "$(dirname "$LONGER")"
printf 'pkg-v1+' >"$LONGER"
expect_pkg_failure "$LONGER" "enclosure length 6 does not match"

# c) Same size, one byte flipped: only the signature can catch it.
FLIPPED="$TMP/flipped/APM44Bridge-9.9.9.pkg"
mkdir -p "$(dirname "$FLIPPED")"
printf 'pkg-v2' >"$FLIPPED"
expect_pkg_failure "$FLIPPED" "edSignature does not verify"

# d) A PKG no enclosure downloads is not silently accepted.
OTHER="$TMP/APM44Bridge-9.9.8.pkg"
cp "$PKG" "$OTHER"
expect_pkg_failure "$OTHER" "0 enclosures for APM44Bridge-9.9.8.pkg"

echo "appcast tests: OK"
