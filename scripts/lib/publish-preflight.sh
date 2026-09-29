# Publication preconditions for scripts/publish-release.sh, sourced so that
# tests/test_publish_preflight.sh can exercise them against temporary Git state
# without running the publish entrypoint. Nothing here creates or uploads
# anything: it only reads local files, Git state, the remote tag and the
# release list.
#
# Inputs (set by the caller): ROOT VERSION TAG REPO DMG PKG DMG_SHA PKG_SHA
# APPCAST. Sets HEAD_SHA for the caller. Refusals go through `fail`, which
# exits the calling shell, so the order of the checks below is the order of
# refusal.

declare -F fail >/dev/null || fail() { echo "error: $*" >&2; exit 1; }

publish_preflight() {
  [[ -z "${APM44_RELEASE_TAG:-}" || "$APM44_RELEASE_TAG" == "$TAG" ]] || \
    fail "APM44_RELEASE_TAG=$APM44_RELEASE_TAG does not match VERSION=$VERSION"

  local command_name
  for command_name in gh git curl shasum python3; do
    command -v "$command_name" >/dev/null 2>&1 || fail "$command_name is required to publish v$VERSION"
  done

  local artifact
  for artifact in "$DMG" "$PKG" "$DMG_SHA" "$PKG_SHA" "$APPCAST"; do
    [[ -f "$artifact" ]] || fail "required gated release artifact is missing: $artifact"
  done

  [[ -z "$(git -C "$ROOT" status --porcelain=v1)" ]] || \
    fail "worktree must be clean before publication; commit docs/appcast.xml and release metadata first"

  HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"
  local tag_sha remote_tag_refs remote_tag_sha
  tag_sha="$(git -C "$ROOT" rev-list -n 1 "$TAG" 2>/dev/null || true)"
  [[ -n "$tag_sha" ]] || fail "signed tag $TAG is missing; create and push it before publishing"
  [[ "$tag_sha" == "$HEAD_SHA" ]] || fail "tag $TAG does not point at HEAD ($HEAD_SHA)"
  remote_tag_refs="$(git -C "$ROOT" ls-remote --tags origin \
    "refs/tags/$TAG" "refs/tags/$TAG^{}")"
  remote_tag_sha="$(awk -v tag="$TAG" '
    $2 == "refs/tags/" tag "^{}" { print $1; found = 1; exit }
    $2 == "refs/tags/" tag { direct = $1 }
    END { if (!found && direct != "") print direct }
  ' <<<"$remote_tag_refs")"
  [[ "$remote_tag_sha" == "$HEAD_SHA" ]] || \
    fail "origin tag $TAG is missing or points to $remote_tag_sha instead of $HEAD_SHA"

  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    fail "GitHub release $TAG already exists; refusing to overwrite it"
  fi
}
