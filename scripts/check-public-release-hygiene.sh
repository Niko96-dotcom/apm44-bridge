#!/usr/bin/env bash
# Fail if maintainer-local or secret-shaped files are tracked in the public tree.
set -euo pipefail

PATTERN='(^|/)\.DS_Store$|^\.planning/|(^|/)\.env($|\.)|\.(p8|p12|pem|key)$|notary-log.*\.json$|build/signing/cert-request/'

tracked_files="$(git ls-files)"
matches="$(printf '%s\n' "$tracked_files" | LC_ALL=C grep -E "$PATTERN" || true)"
if [[ -n "$matches" ]]; then
  echo "error: public release hygiene check failed; tracked private/local files:" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

echo "check-public-release-hygiene: OK"
