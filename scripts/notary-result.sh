#!/usr/bin/env bash
# Shared fail-closed notarytool result handling for release scripts.

extract_notary_submission_id() {
  sed -nE '/^[[:space:]]*id:[[:space:]]*/ {
    s/^[[:space:]]*id:[[:space:]]*([^[:space:]]+).*/\1/
    p
    q
  }'
}

fetch_notary_log_if_available() {
  local submit_output="$1"
  local profile="$2"
  local submission_id=""
  local log_output=""

  submission_id="$(printf '%s\n' "$submit_output" | extract_notary_submission_id)"
  if [[ -z "$submission_id" ]]; then
    return 0
  fi

  echo "Fetching notary log for submission $submission_id..." >&2
  if log_output="$(xcrun notarytool log "$submission_id" --keychain-profile "$profile" 2>&1)"; then
    printf '%s\n' "$log_output" >&2
  else
    echo "warn: failed to fetch notary log for submission $submission_id" >&2
    printf '%s\n' "$log_output" >&2
  fi
}

require_notary_accepted() {
  local artifact="$1"
  local profile="$2"
  local label="${3:-artifact}"
  local output=""
  local submit_status=0

  echo "Submitting $label to notary (profile: $profile)..."
  if output="$(xcrun notarytool submit "$artifact" --keychain-profile "$profile" --wait 2>&1)"; then
    submit_status=0
  else
    submit_status=$?
  fi

  printf '%s\n' "$output"

  if [[ "$submit_status" -ne 0 ]]; then
    echo "error: notarization submit failed for $label (exit $submit_status)" >&2
    fetch_notary_log_if_available "$output" "$profile"
    return "$submit_status"
  fi

  if ! grep -Eq '^[[:space:]]*status:[[:space:]]*Accepted[[:space:]]*$' <<<"$output"; then
    echo "error: notarization did not report status: Accepted for $label" >&2
    fetch_notary_log_if_available "$output" "$profile"
    return 1
  fi
}
