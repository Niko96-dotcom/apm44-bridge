#!/usr/bin/env bash
# Structural and security validation for a Sparkle package-update appcast.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST="${APM44_APPCAST_PATH:-$ROOT/docs/appcast.xml}"
SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"

fail() { echo "error: $*" >&2; exit 1; }
[[ -f "$APPCAST" ]] || fail "appcast missing at $APPCAST"

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$APPCAST" || fail "appcast is not well-formed XML"
else
  python3 - "$APPCAST" <<'PY'
import sys
import xml.etree.ElementTree as ET
try:
    ET.parse(sys.argv[1])
except (OSError, ET.ParseError) as exc:
    raise SystemExit(f"error: appcast is not well-formed XML: {exc}")
PY
fi

python3 - "$APPCAST" <<'PY'
import base64
import sys
import urllib.parse
import xml.etree.ElementTree as ET

path = sys.argv[1]
sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
root = ET.parse(path).getroot()
if root.tag != "rss":
    raise SystemExit("error: appcast root must be rss")
items = root.findall("./channel/item")
if not items:
    raise SystemExit("error: appcast must contain at least one release item")
for item in items:
    version = item.findtext(f"{{{sparkle}}}version")
    enclosure = item.find("enclosure")
    if not version or enclosure is None:
        raise SystemExit("error: every appcast item needs sparkle:version and enclosure")
    url = enclosure.get("url", "")
    if urllib.parse.urlparse(url).scheme != "https":
        raise SystemExit("error: every enclosure URL must use HTTPS")
    if not url.lower().endswith(".pkg"):
        raise SystemExit("error: every enclosure must be the signed .pkg update")
    if enclosure.get(f"{{{sparkle}}}installationType") != "package":
        raise SystemExit("error: package enclosure is missing sparkle:installationType=package")
    signature = enclosure.get(f"{{{sparkle}}}edSignature", "")
    try:
        decoded = base64.b64decode(signature, validate=True)
    except Exception as exc:
        raise SystemExit(f"error: invalid EdDSA enclosure signature: {exc}")
    if len(decoded) != 64:
        raise SystemExit("error: EdDSA enclosure signature must decode to 64 bytes")
    length = enclosure.get("length", "")
    if not length.isdigit() or int(length) <= 0:
        raise SystemExit("error: enclosure length must be a positive integer")
print(f"appcast structure: OK ({len(items)} item(s))")
PY

if [[ -n "$SIGN_UPDATE" ]]; then
  [[ -x "$SIGN_UPDATE" ]] || fail "Sparkle sign_update tool is not executable: $SIGN_UPDATE"
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - --verify "$APPCAST"
  else
    "$SIGN_UPDATE" --verify "$APPCAST"
  fi
  echo "appcast signature: OK"
else
  echo "appcast signature: NOT VERIFIED (set SPARKLE_SIGN_UPDATE for the release gate)" >&2
  exit 1
fi
