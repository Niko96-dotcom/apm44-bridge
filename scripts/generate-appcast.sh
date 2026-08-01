#!/usr/bin/env bash
# Generate and sign the HTTPS Sparkle appcast for the signed release PKG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$($ROOT/scripts/read-version.sh)"
PKG="${APM44_RELEASE_PKG:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
APPCAST="${APM44_APPCAST_PATH:-$ROOT/docs/appcast.xml}"
RELEASE_URL="${APM44_RELEASE_URL:-https://github.com/Niko96-dotcom/apm44-bridge/releases/download/v${VERSION}/APM44Bridge-${VERSION}.pkg}"
RELEASE_NOTES_URL="${APM44_RELEASE_NOTES_URL:-https://github.com/Niko96-dotcom/apm44-bridge/releases/tag/v${VERSION}}"

[[ -f "$PKG" ]] || { echo "error: signed release PKG missing at $PKG" >&2; exit 1; }
[[ "$RELEASE_URL" == https://* ]] || { echo "error: release URL must use HTTPS" >&2; exit 1; }

SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-$($ROOT/scripts/ensure-sparkle-tools.sh)}"
[[ -x "$SIGN_UPDATE" ]] || { echo "error: Sparkle sign_update tool is not executable: $SIGN_UPDATE" >&2; exit 1; }

run_sign_update() {
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    # The secret is piped directly to Sparkle and is never written, echoed, or
    # included in an argument list. Local releases normally use the Keychain.
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$@"
  else
    "$SIGN_UPDATE" "$@"
  fi
}

signature_fragment="$(run_sign_update -p "$PKG")"
signature="$(printf '%s\n' "$signature_fragment" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
if [[ -z "$signature" ]]; then
  # Sparkle 2.9's -p mode emits the raw base64 Ed25519 signature. Keep the
  # attribute parser above for older tool builds that print XML metadata.
  signature="$(printf '%s' "$signature_fragment" | tr -d '[:space:]')"
fi
length="$(stat -f%z "$PKG")"
[[ "$signature" =~ ^[A-Za-z0-9+/=]+$ ]] || {
  echo "error: Sparkle sign_update did not return an EdDSA signature" >&2
  exit 1
}
python3 - "$signature" <<'PY'
import base64
import sys
try:
    decoded = base64.b64decode(sys.argv[1], validate=True)
except Exception as exc:
    raise SystemExit(f"error: invalid Sparkle EdDSA signature: {exc}")
if len(decoded) != 64:
    raise SystemExit("error: Sparkle EdDSA signature must decode to 64 bytes")
PY
[[ "$length" =~ ^[1-9][0-9]*$ ]] || { echo "error: invalid PKG length: $length" >&2; exit 1; }

mkdir -p "$(dirname "$APPCAST")"
temp_appcast="$(mktemp "$(dirname "$APPCAST")/.appcast.XXXXXX.xml")"
cleanup() { rm -f "$temp_appcast"; }
trap cleanup EXIT

cat >"$temp_appcast" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>APM44 Bridge Updates</title>
    <link>https://github.com/Niko96-dotcom/apm44-bridge</link>
    <description>Signed APM44 Bridge updates</description>
    <language>en</language>
    <item>
      <title>APM44 Bridge ${VERSION}</title>
      <link>${RELEASE_NOTES_URL}</link>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>${RELEASE_NOTES_URL}</sparkle:releaseNotesLink>
      <sparkle:fullReleaseNotesLink>https://github.com/Niko96-dotcom/apm44-bridge/blob/main/CHANGELOG.md</sparkle:fullReleaseNotesLink>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <enclosure url="${RELEASE_URL}"
                 sparkle:edSignature="${signature}"
                 sparkle:installationType="package"
                 length="${length}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

# SURequireSignedFeed is enabled in the app, so sign the complete feed after
# writing the enclosure metadata. Sparkle embeds the feed signature in-place.
run_sign_update --disable-signing-warning "$temp_appcast" >/dev/null
mv "$temp_appcast" "$APPCAST"
trap - EXIT
echo "Signed appcast: $APPCAST"
echo "Appcast release: v${VERSION} -> ${RELEASE_URL}"
