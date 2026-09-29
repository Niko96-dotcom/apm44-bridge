#!/usr/bin/env bash
# Credential-free regression tests for the publication preconditions in
# scripts/lib/publish-preflight.sh. They run against temporary Git repositories
# with a local bare "origin" and PATH shims for `git` and `gh` that log every
# call. Only read-only calls are allowed: any other git/gh call is recorded as
# a mutation, refused, and fails the test. scripts/publish-release.sh itself is
# never executed here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/scripts/lib/publish-preflight.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REAL_GIT="$(command -v git)"
SHIMS="$TMP/shims"
CALLS="$TMP/calls.log"
MUTATIONS="$TMP/mutations.log"
mkdir -p "$SHIMS"

# git: delegate the read-only subcommands preflight needs, refuse the rest.
cat >"$SHIMS/git" <<SHIM
#!/bin/bash
args=("\$@")
[[ "\${args[0]:-}" == "-C" ]] && args=("\${args[@]:2}")
echo "git \$*" >>"$CALLS"
case "\${args[0]:-}" in
  status|rev-parse|rev-list|ls-remote) exec "$REAL_GIT" "\$@" ;;
  *) echo "git \$*" >>"$MUTATIONS"; echo "fake git: refused \$*" >&2; exit 99 ;;
esac
SHIM

# gh: only `release view` is a read; whether the release exists is a fixture.
cat >"$SHIMS/gh" <<SHIM
#!/bin/bash
echo "gh \$*" >>"$CALLS"
if [[ "\${1:-}" == "release" && "\${2:-}" == "view" ]]; then
  [[ "\${FAKE_GH_RELEASE_EXISTS:-0}" == "1" ]] && exit 0
  exit 1
fi
echo "gh \$*" >>"$MUTATIONS"
echo "fake gh: refused \$*" >&2
exit 99
SHIM
chmod +x "$SHIMS/git" "$SHIMS/gh"

TAG="v1.2.3"
VERSION="1.2.3"

# Builds a fresh repo with a bare origin, one commit, the release artifacts, and
# (by default) an annotated tag at HEAD pushed to origin. Prints the repo path.
new_repo() {
  local name="$1" repo="$TMP/$1/repo" origin="$TMP/$1/origin.git"
  mkdir -p "$repo"
  "$REAL_GIT" init -q --bare "$origin"
  "$REAL_GIT" init -q "$repo"
  "$REAL_GIT" -C "$repo" config user.name test
  "$REAL_GIT" -C "$repo" config user.email test@example.invalid
  "$REAL_GIT" -C "$repo" config commit.gpgsign false
  "$REAL_GIT" -C "$repo" config tag.gpgsign false
  "$REAL_GIT" -C "$repo" remote add origin "$origin"
  echo one >"$repo/file"
  mkdir -p "$repo/art"
  for f in a.dmg a.pkg a.dmg.sha256 a.pkg.sha256 appcast.xml; do echo x >"$repo/art/$f"; done
  "$REAL_GIT" -C "$repo" add file
  "$REAL_GIT" -C "$repo" commit -q -m one
  "$REAL_GIT" -C "$repo" tag -a "$TAG" -m release
  "$REAL_GIT" -C "$repo" push -q origin HEAD:refs/heads/main "refs/tags/$TAG"
  # The artifacts are outside the tracked tree so they never dirty it.
  echo "art/" >>"$repo/.git/info/exclude"
  echo "$repo"
}

# Runs publish_preflight in a subshell exactly as publish-release.sh does
# (plain call under set -e). Prints combined output; returns its exit status.
run_preflight() {
  local repo="$1"
  : >"$CALLS"
  : >"$MUTATIONS"
  env PATH="$SHIMS:$PATH" \
    ROOT="$repo" VERSION="$VERSION" TAG="$TAG" REPO="example/repo" \
    DMG="$repo/art/a.dmg" PKG="$repo/art/a.pkg" \
    DMG_SHA="$repo/art/a.dmg.sha256" PKG_SHA="$repo/art/a.pkg.sha256" \
    APPCAST="$repo/art/appcast.xml" \
    LIB="$LIB" \
    /bin/bash -c 'set -euo pipefail; source "$LIB"; publish_preflight; echo "HEAD_SHA=$HEAD_SHA"' 2>&1
}

assert_no_mutation() {
  if [[ -s "$MUTATIONS" ]]; then
    echo "$1: preflight attempted a mutating call:" >&2
    cat "$MUTATIONS" >&2
    exit 1
  fi
}

expect_refusal() {
  local name="$1" repo="$2" expected="$3" output
  if output="$(run_preflight "$repo")"; then
    echo "$name: expected preflight to refuse" >&2
    exit 1
  fi
  [[ "$output" == *"$expected"* ]] || {
    echo "$name: expected '$expected', got: $output" >&2
    exit 1
  }
  assert_no_mutation "$name"
}

expect_gh_not_called() {
  if grep -q '^gh ' "$CALLS"; then
    echo "$1: gh was consulted although an earlier gate had already refused" >&2
    exit 1
  fi
}

# Valid: clean tree, tag at HEAD locally and on origin, no release yet.
repo="$(new_repo valid)"
if ! output="$(run_preflight "$repo")"; then
  echo "valid: expected preflight to pass, got: $output" >&2
  exit 1
fi
[[ "$output" == *"HEAD_SHA=$("$REAL_GIT" -C "$repo" rev-parse HEAD)"* ]] || {
  echo "valid: preflight did not export HEAD_SHA: $output" >&2
  exit 1
}
grep -q '^gh release view v1.2.3 --repo example/repo' "$CALLS" || {
  echo "valid: the existing-release gate was never consulted" >&2
  exit 1
}
assert_no_mutation valid

# Dirty tree: tracked modification, and an untracked file.
repo="$(new_repo dirty-tracked)"
echo two >>"$repo/file"
expect_refusal dirty-tracked "$repo" "worktree must be clean"
expect_gh_not_called dirty-tracked
repo="$(new_repo dirty-untracked)"
echo new >"$repo/untracked"
expect_refusal dirty-untracked "$repo" "worktree must be clean"

# Local tag missing.
repo="$(new_repo tag-missing)"
"$REAL_GIT" -C "$repo" tag -d "$TAG" >/dev/null
expect_refusal tag-missing "$repo" "signed tag v1.2.3 is missing"
expect_gh_not_called tag-missing

# Local tag exists but HEAD moved on.
repo="$(new_repo tag-behind-head)"
echo two >>"$repo/file"
"$REAL_GIT" -C "$repo" commit -q -am two
expect_refusal tag-behind-head "$repo" "tag v1.2.3 does not point at HEAD"
expect_gh_not_called tag-behind-head

# Tag not on origin.
repo="$(new_repo remote-tag-missing)"
"$REAL_GIT" -C "$repo" push -q origin ":refs/tags/$TAG"
expect_refusal remote-tag-missing "$repo" "origin tag v1.2.3 is missing or points to"
expect_gh_not_called remote-tag-missing

# Tag on origin points at a different commit than the local tag/HEAD.
repo="$(new_repo remote-tag-moved)"
"$REAL_GIT" -C "$repo" push -q origin ":refs/tags/$TAG"
first_commit="$("$REAL_GIT" -C "$repo" rev-parse HEAD)"
echo two >>"$repo/file"
"$REAL_GIT" -C "$repo" commit -q -am two
"$REAL_GIT" -C "$repo" tag -a -f "$TAG" -m moved >/dev/null
"$REAL_GIT" -C "$repo" push -q origin "$first_commit:refs/tags/$TAG"
expect_refusal remote-tag-moved "$repo" "origin tag v1.2.3 is missing or points to"
expect_gh_not_called remote-tag-moved

# The release already exists: refused, after every other gate passed.
repo="$(new_repo release-exists)"
FAKE_GH_RELEASE_EXISTS=1 expect_refusal release-exists "$repo" "GitHub release v1.2.3 already exists"
grep -q '^gh release view' "$CALLS" || {
  echo "release-exists: the release list was not consulted" >&2
  exit 1
}

# Gate order is preserved: with several problems at once, the earliest reports.
repo="$(new_repo order)"
echo two >>"$repo/file"
"$REAL_GIT" -C "$repo" tag -d "$TAG" >/dev/null
FAKE_GH_RELEASE_EXISTS=1 expect_refusal order-dirty-before-tag "$repo" "worktree must be clean"
"$REAL_GIT" -C "$repo" checkout -q -- file
FAKE_GH_RELEASE_EXISTS=1 expect_refusal order-tag-before-release "$repo" "signed tag v1.2.3 is missing"

# Earlier gates: a missing gated artifact and a mismatched release tag override.
repo="$(new_repo artifact-missing)"
rm "$repo/art/a.pkg"
expect_refusal artifact-missing "$repo" "required gated release artifact is missing"
expect_gh_not_called artifact-missing
repo="$(new_repo tag-override)"
APM44_RELEASE_TAG=v9.9.9 expect_refusal tag-override "$repo" "APM44_RELEASE_TAG=v9.9.9 does not match"
expect_gh_not_called tag-override

# The shims really do refuse a publication call (they would fail the tests above
# if preflight ever made one), and the entrypoint is wired to the sourced gate.
: >"$MUTATIONS"
if PATH="$SHIMS:$PATH" gh release create v1.2.3 >/dev/null 2>&1; then
  echo "shim self-check: gh release create was not refused" >&2
  exit 1
fi
[[ -s "$MUTATIONS" ]] || { echo "shim self-check: mutation was not recorded" >&2; exit 1; }
: >"$MUTATIONS"

publish="$ROOT/scripts/publish-release.sh"
grep -Fq 'source "$ROOT/scripts/lib/publish-preflight.sh"' "$publish"
preflight_line="$(grep -n '^publish_preflight$' "$publish" | cut -d: -f1)"
create_line="$(grep -n 'gh release create' "$publish" | head -1 | cut -d: -f1)"
[[ -n "$preflight_line" && -n "$create_line" && "$preflight_line" -lt "$create_line" ]] || {
  echo "publish-release.sh must run publish_preflight before gh release create" >&2
  exit 1
}

echo "publish preflight tests: OK"
