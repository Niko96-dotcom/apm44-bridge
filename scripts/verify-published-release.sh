#!/usr/bin/env bash
# Verify public release downloads without GitHub authentication.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$($ROOT/scripts/read-version.sh)"
REPO="${APM44_GITHUB_REPO:-Niko96-dotcom/apm44-bridge}"
BASE="https://github.com/${REPO}/releases/download/v${VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "error: $*" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v shasum >/dev/null 2>&1 || fail "shasum is required"

download() {
  local name="$1"
  curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    "$BASE/$name" --output "$TMP/$name"
  [[ -s "$TMP/$name" ]] || fail "downloaded asset is empty: $name"
}

for name in \
  "APM44Bridge-${VERSION}.dmg" \
  "APM44Bridge-${VERSION}.pkg" \
  "APM44Bridge-${VERSION}.dmg.sha256" \
  "APM44Bridge-${VERSION}.pkg.sha256"; do
  echo "Downloading $name..."
  download "$name"
done

(cd "$TMP" && shasum -a 256 -c "APM44Bridge-${VERSION}.dmg.sha256")
(cd "$TMP" && shasum -a 256 -c "APM44Bridge-${VERSION}.pkg.sha256")

APPCAST="$TMP/appcast.xml"
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
  "https://niko96-dotcom.github.io/apm44-bridge/appcast.xml" --output "$APPCAST"

python3 - "$APPCAST" "$VERSION" "$BASE/APM44Bridge-${VERSION}.pkg" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, version, expected_url = sys.argv[1:]
sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
root = ET.parse(path).getroot()
for item in root.findall("./channel/item"):
    if item.findtext(f"{{{sparkle}}}version") != version:
        continue
    enclosure = item.find("enclosure")
    if enclosure is not None and enclosure.get("url") == expected_url:
        raise SystemExit(0)
raise SystemExit(
    f"error: hosted appcast has no v{version} item pointing at {expected_url}"
)
PY

APM44_APPCAST_PATH="$APPCAST" \
  SPARKLE_SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}" \
  bash "$ROOT/scripts/validate-appcast.sh"

echo "verify-published-release: OK (v$VERSION, unauthenticated downloads)"
