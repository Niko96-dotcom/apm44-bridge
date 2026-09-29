#!/usr/bin/env bash
# Credential-free regression tests for Sparkle package appcast validation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

grep -Fq '<key>SUFeedURL</key>' "$ROOT/App/APM44Bridge/Info.plist"
grep -Fq '<key>SUPublicEDKey</key>' "$ROOT/App/APM44Bridge/Info.plist"
grep -Fq '<key>SUEnableAutomaticChecks</key>' "$ROOT/App/APM44Bridge/Info.plist"
grep -Fq 'sparkle:installationType="package"' "$ROOT/scripts/generate-appcast.sh"
grep -Fq 'sparkle:format="markdown"' "$ROOT/scripts/generate-appcast.sh"

# The updater security settings are verified by parsed value and type, not by
# key presence: a flipped, missing or string-typed value must fail.
VERIFY_SECURITY="$ROOT/scripts/verify-updater-security.sh"
security_plist() {
  local path="$1" signed="$2" verify="$3" auto="$4"
  cat >"$path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
$signed
$verify
$auto
</dict></plist>
PLIST
}
SEC_SIGNED='<key>SURequireSignedFeed</key><true/>'
SEC_VERIFY='<key>SUVerifyUpdateBeforeExtraction</key><true/>'
SEC_AUTO='<key>SUAutomaticallyUpdate</key><false/>'

expect_security_failure() {
  local name="$1" expected="$2" output
  if output="$(/bin/bash "$VERIFY_SECURITY" "$TMP/$name.plist" 2>&1)"; then
    echo "expected updater security verification to fail for $name" >&2
    exit 1
  fi
  [[ "$output" == *"$expected"* ]] || {
    echo "expected '$expected' for $name, got: $output" >&2
    exit 1
  }
}

security_plist "$TMP/sec-good.plist" "$SEC_SIGNED" "$SEC_VERIFY" "$SEC_AUTO"
/bin/bash "$VERIFY_SECURITY" "$TMP/sec-good.plist" >/dev/null

# An app bundle path resolves to Contents/Info.plist.
mkdir -p "$TMP/Fake.app/Contents"
cp "$TMP/sec-good.plist" "$TMP/Fake.app/Contents/Info.plist"
/bin/bash "$VERIFY_SECURITY" "$TMP/Fake.app" >/dev/null

# Flipped values.
security_plist "$TMP/sec-signed-false.plist" '<key>SURequireSignedFeed</key><false/>' "$SEC_VERIFY" "$SEC_AUTO"
expect_security_failure sec-signed-false "SURequireSignedFeed must be true"
security_plist "$TMP/sec-verify-false.plist" "$SEC_SIGNED" '<key>SUVerifyUpdateBeforeExtraction</key><false/>' "$SEC_AUTO"
expect_security_failure sec-verify-false "SUVerifyUpdateBeforeExtraction must be true"
security_plist "$TMP/sec-auto-true.plist" "$SEC_SIGNED" "$SEC_VERIFY" '<key>SUAutomaticallyUpdate</key><true/>'
expect_security_failure sec-auto-true "SUAutomaticallyUpdate must be false"

# Missing keys.
security_plist "$TMP/sec-signed-missing.plist" '' "$SEC_VERIFY" "$SEC_AUTO"
expect_security_failure sec-signed-missing "SURequireSignedFeed is missing"
security_plist "$TMP/sec-verify-missing.plist" "$SEC_SIGNED" '' "$SEC_AUTO"
expect_security_failure sec-verify-missing "SUVerifyUpdateBeforeExtraction is missing"
security_plist "$TMP/sec-auto-missing.plist" "$SEC_SIGNED" "$SEC_VERIFY" ''
expect_security_failure sec-auto-missing "SUAutomaticallyUpdate is missing"

# Wrong types: strings and integers are not Booleans, even when they read "true".
security_plist "$TMP/sec-signed-string.plist" '<key>SURequireSignedFeed</key><string>true</string>' "$SEC_VERIFY" "$SEC_AUTO"
expect_security_failure sec-signed-string "SURequireSignedFeed must be a Boolean"
security_plist "$TMP/sec-verify-integer.plist" "$SEC_SIGNED" '<key>SUVerifyUpdateBeforeExtraction</key><integer>1</integer>' "$SEC_AUTO"
expect_security_failure sec-verify-integer "SUVerifyUpdateBeforeExtraction must be a Boolean"
security_plist "$TMP/sec-auto-string.plist" "$SEC_SIGNED" "$SEC_VERIFY" '<key>SUAutomaticallyUpdate</key><string>false</string>'
expect_security_failure sec-auto-string "SUAutomaticallyUpdate must be a Boolean"

# Unusable input.
printf 'not a plist' >"$TMP/sec-garbage.plist"
expect_security_failure sec-garbage "not a valid property list"
if /bin/bash "$VERIFY_SECURITY" "$TMP/does-not-exist.plist" >/dev/null 2>&1; then
  echo "expected updater security verification to fail for a missing file" >&2
  exit 1
fi

# The shipped source plist must satisfy the same gate.
/bin/bash "$VERIFY_SECURITY" "$ROOT/App/APM44Bridge/Info.plist" >/dev/null

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

# The candidate must advertise the intended version in BOTH version fields. The
# intended version comes from VERSION, never from the feed under test.
INTENDED="$(/bin/bash "$ROOT/scripts/read-version.sh")"
grep -Fq "<sparkle:version>${INTENDED}</sparkle:version>" "$GENERATED"
grep -Fq "<sparkle:shortVersionString>${INTENDED}</sparkle:shortVersionString>" "$GENERATED"

# Validates FEED with --expect-version; prints stderr, returns the exit status.
validate_expect() {
  local feed="$1"
  shift
  env -u SPARKLE_PRIVATE_KEY \
    APM44_APPCAST_PATH="$feed" \
    SPARKLE_SIGN_UPDATE="$PKG_SIGNER" \
    /bin/bash "$ROOT/scripts/validate-appcast.sh" "$@" 2>&1 >/dev/null
}

expect_version_failure() {
  local feed="$1" expected="$2" output
  shift 2
  if output="$(validate_expect "$feed" "$@")"; then
    echo "expected --expect-version validation to fail for $feed" >&2
    exit 1
  fi
  [[ "$output" == *"$expected"* ]] || {
    echo "expected '$expected' from --expect-version validation, got: $output" >&2
    exit 1
  }
}

# e) The generated candidate passes, alone and together with --pkg.
if ! output="$(validate_expect "$GENERATED" --expect-version "$INTENDED")"; then
  echo "expected generated feed to pass --expect-version, got: $output" >&2
  exit 1
fi
if ! output="$(validate_expect "$GENERATED" --pkg "$PKG" --expect-version "$INTENDED")"; then
  echo "expected generated feed to pass --pkg with --expect-version, got: $output" >&2
  exit 1
fi

# f) Each field fails independently when it diverges from the intended version.
WRONG_VERSION="$TMP/wrong-version.xml"
sed 's#<sparkle:version>[^<]*</sparkle:version>#<sparkle:version>0.0.1</sparkle:version>#' "$GENERATED" >"$WRONG_VERSION"
expect_version_failure "$WRONG_VERSION" "candidate sparkle:version is '0.0.1'" --expect-version "$INTENDED"
WRONG_SHORT="$TMP/wrong-short.xml"
sed 's#<sparkle:shortVersionString>[^<]*</sparkle:shortVersionString>#<sparkle:shortVersionString>0.0.1</sparkle:shortVersionString>#' "$GENERATED" >"$WRONG_SHORT"
expect_version_failure "$WRONG_SHORT" "candidate sparkle:shortVersionString is '0.0.1'" --expect-version "$INTENDED"

# g) A missing field fails; shortVersionString is not required by the default mode.
NO_VERSION="$TMP/no-version.xml"
NO_SHORT="$TMP/no-short.xml"
sed '/<sparkle:shortVersionString>/d' "$GENERATED" >"$NO_SHORT"
expect_version_failure "$NO_SHORT" "missing sparkle:shortVersionString" --expect-version "$INTENDED"
python3 - "$GENERATED" "$NO_VERSION" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(re.sub(r"\s*<sparkle:version>[^<]*</sparkle:version>", "", text, count=1))
PY
# Without sparkle:version the structural check rejects it before the comparison.
if validate_expect "$NO_VERSION" --expect-version "$INTENDED" >/dev/null; then
  echo "expected a feed without sparkle:version to fail" >&2
  exit 1
fi
env -u SPARKLE_PRIVATE_KEY APM44_APPCAST_PATH="$NO_SHORT" SPARKLE_SIGN_UPDATE="$PKG_SIGNER" \
  /bin/bash "$ROOT/scripts/validate-appcast.sh" >/dev/null

# h) Historical multi-item feeds still validate without an expected version, and
# older items after the candidate are not held to the intended version.
HISTORICAL="$TMP/historical.xml"
python3 - "$GENERATED" "$HISTORICAL" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
item = re.search(r"    <item>.*?</item>\n", text, re.S).group(0)
older = item.replace("APM44 Bridge", "APM44 Bridge (old)")
older = re.sub(r"(<sparkle:(?:version|shortVersionString)>)[^<]*", r"\g<1>0.0.1", older)
open(sys.argv[2], "w").write(text.replace(item, item + older))
PY
grep -Fc '<sparkle:version>0.0.1</sparkle:version>' "$HISTORICAL" | grep -qx 1
if ! output="$(validate_expect "$HISTORICAL")"; then
  echo "expected historical multi-item feed to pass without --expect-version, got: $output" >&2
  exit 1
fi
if ! output="$(validate_expect "$HISTORICAL" --expect-version "$INTENDED")"; then
  echo "expected older items after the candidate to be accepted, got: $output" >&2
  exit 1
fi
# An old item in the candidate position is not mistaken for the candidate.
OLD_FIRST="$TMP/old-first.xml"
python3 - "$HISTORICAL" "$OLD_FIRST" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
first, second = re.findall(r"    <item>.*?</item>\n", text, re.S)
open(sys.argv[2], "w").write(text.replace(first + second, second + first))
PY
expect_version_failure "$OLD_FIRST" "candidate sparkle:version is '0.0.1'" --expect-version "$INTENDED"

# i) Byte and signature failures are still enforced alongside --expect-version.
expect_version_failure "$GENERATED" "enclosure length 6 does not match" \
  --pkg "$LONGER" --expect-version "$INTENDED"
expect_version_failure "$GENERATED" "edSignature does not verify" \
  --pkg "$FLIPPED" --expect-version "$INTENDED"

echo "appcast tests: OK"
