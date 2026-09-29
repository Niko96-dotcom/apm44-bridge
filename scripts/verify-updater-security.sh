#!/usr/bin/env bash
# Assert the Sparkle security settings baked into an app's Info.plist.
#
# Usage: verify-updater-security.sh <app bundle | Info.plist>
#
# Each key must be present as a real plist Boolean with the required value:
#   SURequireSignedFeed            true   feed must carry a valid EdDSA signature
#   SUVerifyUpdateBeforeExtraction true   verify the download before unpacking it
#   SUAutomaticallyUpdate          false  never install updates without the user
# SUAutomaticallyUpdate is required to be present even though Sparkle's default
# is also false, so removing the explicit opt-out is caught rather than trusted.
# A string "true" or an integer 1 is rejected: it is not what the source ships.
set -euo pipefail

fail() { echo "error: $*" >&2; exit 1; }

[[ $# -eq 1 && -n "$1" ]] || fail "usage: verify-updater-security.sh <app bundle | Info.plist>"
target="$1"
if [[ -d "$target" ]]; then
  plist="$target/Contents/Info.plist"
else
  plist="$target"
fi
[[ -f "$plist" ]] || fail "Info.plist missing at $plist"
plutil -lint "$plist" >/dev/null 2>&1 || fail "$plist is not a valid property list"

require_bool() {
  local key="$1" want="$2" type value
  type="$(plutil -type "$key" "$plist" 2>/dev/null)" || fail "$key is missing from $plist"
  [[ "$type" == "bool" ]] || fail "$key must be a Boolean, found type '$type' in $plist"
  value="$(plutil -extract "$key" raw -o - "$plist")"
  [[ "$value" == "$want" ]] || fail "$key must be $want, found $value in $plist"
}

require_bool SURequireSignedFeed true
require_bool SUVerifyUpdateBeforeExtraction true
require_bool SUAutomaticallyUpdate false
echo "updater security: OK ($plist)"
