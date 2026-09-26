#!/usr/bin/env bash
# Build a local signed Sparkle feed for end-to-end update testing.
# Copies the candidate pkg to <out>/test.pkg and writes <out>/appcast.xml,
# signs it with sign_update and verifies the signature.
# Does NOT start an HTTP server (see e2e-update-roundtrip.sh).
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: e2e-local-update-feed.sh --pkg <pkg> --version <label> --out <dir> [--port 8765] [--sign-update <path>]

Copies <pkg> to <dir>/test.pkg and writes <dir>/appcast.xml with one item.
sparkle:version and sparkle:shortVersionString are <label>. The enclosure url
is http://127.0.0.1:<port>/test.pkg with the edSignature from `sign_update -p`,
the file-size length, sparkle:installationType="package" and
type="application/octet-stream".

Signs the feed with `sign_update <xml>` and verifies it with
`sign_update --verify`. Fails if verification fails.

sign_update defaults to $SPARKLE_SIGN_UPDATE or the output of
`bash scripts/ensure-sparkle-tools.sh`. Does NOT start a server.
USAGE
}

PKG=""
LABEL=""
OUT=""
PORT="8765"
SIGN_UPDATE_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --pkg)
      PKG="${2:-}"
      shift 2
      ;;
    --version)
      LABEL="${2:-}"
      shift 2
      ;;
    --out)
      OUT="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --sign-update)
      SIGN_UPDATE_ARG="${2:-}"
      shift 2
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$PKG" || -z "$LABEL" || -z "$OUT" ]]; then
  echo "error: --pkg, --version and --out are required" >&2
  usage >&2
  exit 2
fi

RUN_DIR="$(mktemp -d)"
echo "run dir: $RUN_DIR"
cleanup() {
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SIGN_UPDATE=""
if [[ -n "$SIGN_UPDATE_ARG" ]]; then
  SIGN_UPDATE="$SIGN_UPDATE_ARG"
elif [[ -n "${SPARKLE_SIGN_UPDATE:-}" ]]; then
  SIGN_UPDATE="$SPARKLE_SIGN_UPDATE"
else
  SIGN_UPDATE="$(bash "$SCRIPT_DIR/ensure-sparkle-tools.sh" || true)"
fi

if [[ -z "$SIGN_UPDATE" || ! -x "$SIGN_UPDATE" ]]; then
  echo "error: Sparkle sign_update tool is not executable: ${SIGN_UPDATE:-<empty>}" >&2
  echo "hint: set SPARKLE_SIGN_UPDATE or run scripts/ensure-sparkle-tools.sh" >&2
  exit 1
fi

if [[ ! -f "$PKG" ]]; then
  echo "error: pkg missing at $PKG" >&2
  exit 1
fi

mkdir -p "$OUT"
cp "$PKG" "$OUT/test.pkg"

LENGTH="$(wc -c <"$OUT/test.pkg" | tr -d '[:space:]')"
if [[ -z "$LENGTH" || "$LENGTH" == "0" ]]; then
  echo "error: could not determine pkg length" >&2
  exit 1
fi

SIG_FRAGMENT="$("$SIGN_UPDATE" -p "$OUT/test.pkg")"
SIG="$(printf '%s\n' "$SIG_FRAGMENT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
if [[ -z "$SIG" ]]; then
  SIG="$(printf '%s' "$SIG_FRAGMENT" | tr -d '[:space:]')"
fi
if [[ -z "$SIG" ]]; then
  echo "error: sign_update -p did not return a signature" >&2
  exit 1
fi

APPCAST="$OUT/appcast.xml"
PUBDATE="$(LC_ALL=C date -R 2>/dev/null || date)"
ENC_URL="http://127.0.0.1:${PORT}/test.pkg"

cat >"$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>APM44 Bridge Local Test Feed</title>
    <link>http://127.0.0.1:${PORT}/</link>
    <description>Local e2e update feed</description>
    <language>en</language>
    <item>
      <title>APM44 Bridge ${LABEL}</title>
      <sparkle:version>${LABEL}</sparkle:version>
      <sparkle:shortVersionString>${LABEL}</sparkle:shortVersionString>
      <description>Local test update ${LABEL}</description>
      <pubDate>${PUBDATE}</pubDate>
      <enclosure url="${ENC_URL}"
                 sparkle:edSignature="${SIG}"
                 sparkle:installationType="package"
                 length="${LENGTH}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

"$SIGN_UPDATE" "$APPCAST" >/dev/null
if ! "$SIGN_UPDATE" --verify "$APPCAST" >/dev/null 2>&1; then
  echo "error: feed signature verification failed for $APPCAST" >&2
  exit 1
fi

echo "feed ready: $APPCAST"
echo "enclosure: $ENC_URL length=$LENGTH"
