#!/usr/bin/env bash
# Structural and security validation for a Sparkle package-update appcast.
#
# Usage: validate-appcast.sh [--pkg <path>]
#   --pkg  also require the enclosure that downloads <path> (matched by file
#          name) to carry that file's byte length and a verifying EdDSA
#          signature, so a PKG rebuilt after generate-appcast.sh cannot ship.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST="${APM44_APPCAST_PATH:-$ROOT/docs/appcast.xml}"
SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"
PKG=""

fail() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pkg)
      [[ $# -ge 2 && -n "$2" ]] || fail "--pkg needs a path"
      PKG="$2"
      shift 2
      ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -f "$APPCAST" ]] || fail "appcast missing at $APPCAST"
[[ -z "$PKG" || -f "$PKG" ]] || fail "PKG missing at $PKG"

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
    release_notes_link = item.find(f"{{{sparkle}}}releaseNotesLink")
    description = item.find("description")
    if release_notes_link is not None:
        notes_url = release_notes_link.text or ""
        if urllib.parse.urlparse(notes_url).scheme != "https":
            raise SystemExit("error: release notes URL must use HTTPS")
        notes_signature = release_notes_link.get(f"{{{sparkle}}}edSignature", "")
        try:
            notes_decoded = base64.b64decode(notes_signature, validate=True)
        except Exception as exc:
            raise SystemExit(f"error: invalid EdDSA release notes signature: {exc}")
        if len(notes_decoded) != 64:
            raise SystemExit("error: release notes EdDSA signature must decode to 64 bytes")
        notes_length = release_notes_link.get("length", "")
        if not notes_length.isdigit() or int(notes_length) <= 0:
            raise SystemExit("error: release notes length must be a positive integer")
    elif description is None or not (description.text or "").strip():
        raise SystemExit("error: every appcast item needs embedded release notes or a signed releaseNotesLink")
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

if [[ -z "$SIGN_UPDATE" ]]; then
  echo "appcast signature: NOT VERIFIED (set SPARKLE_SIGN_UPDATE for the release gate)" >&2
  exit 1
fi
[[ -x "$SIGN_UPDATE" ]] || fail "Sparkle sign_update tool is not executable: $SIGN_UPDATE"

run_sign_update() {
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$@"
  else
    "$SIGN_UPDATE" "$@"
  fi
}

run_sign_update --verify "$APPCAST"
echo "appcast signature: OK"

[[ -n "$PKG" ]] || exit 0

# Prints "<length> <edSignature>" of the one enclosure whose URL file name is
# the PKG's file name. Both values were already checked for shape above.
enclosure="$(python3 - "$APPCAST" "$(basename "$PKG")" <<'PY'
import posixpath
import sys
import urllib.parse
import xml.etree.ElementTree as ET

path, name = sys.argv[1:]
sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
matches = [
    enclosure
    for enclosure in ET.parse(path).getroot().findall("./channel/item/enclosure")
    if posixpath.basename(urllib.parse.urlparse(enclosure.get("url", "")).path) == name
]
if len(matches) != 1:
    raise SystemExit(f"error: appcast has {len(matches)} enclosures for {name}, expected 1")
print(matches[0].get("length"), matches[0].get(f"{{{sparkle}}}edSignature"))
PY
)"
enclosure_length="${enclosure%% *}"
enclosure_signature="${enclosure#* }"

pkg_length="$(stat -L -f%z "$PKG")"
[[ "$pkg_length" == "$enclosure_length" ]] || \
  fail "enclosure length $enclosure_length does not match $PKG ($pkg_length bytes)"
run_sign_update --verify "$PKG" "$enclosure_signature" >/dev/null || \
  fail "enclosure edSignature does not verify against $PKG"
echo "appcast enclosure matches PKG: OK ($(basename "$PKG"), $pkg_length bytes)"
