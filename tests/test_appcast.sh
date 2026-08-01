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

echo "appcast tests: OK"
