---
name: apm44-release
description: "Release, publish, or verify APM44 Bridge, or run its E2E installed-update test. Use for version bumps, release builds, appcast/tag/publish, Pages verification, or the candidate update round trip."
argument-hint: "[X.Y.Z | --e2e-only | --verify-only]"
---

# APM44 Bridge Release

You are doing a maintainer release. Follow the steps in order. Do not skip.
`X.Y.Z` below means the version in the `VERSION` file.

## 1. Preconditions and authority (read first, no exceptions)

1. Publishing version X.Y.Z needs explicit user approval for X.Y.Z. STOP if not given: ask for it and do nothing else.
2. Never merge when CI is pending or failing (see Step 1).
3. Never type passwords. Never approve the macOS admin prompt yourself; only the human does (see Step 4).
4. Never run the real preinstall or postinstall scripts directly. See `references/troubleshooting.md` for the guard-only test form.
5. Never install an older PKG over a newer installed app. Check versions first; STOP if the candidate is older than the install.
6. Work in the repository root (the checkout of Niko96-dotcom/apm44-bridge) on `main`; run every command from there. The merge policy allows rebase or squash only (no merge commits).

## 2. Release checklist (copy, fill X.Y.Z, tick as you go)

```text
Version: X.Y.Z
[ ] Step 1 PR merged, CI all pass/skipping
[ ] Step 2 VERSION+CHANGELOG bumped, pushed
[ ] Step 3 release-all.sh built, log shows 3x Accepted + signature OK + identity OK
[ ] Step 4 E2E round trip PASS on the candidate BEFORE publishing (human approved once)
[ ] Step 5 appcast committed, signed tag vX.Y.Z at HEAD, pushed
[ ] Step 6 publish-release.sh succeeded
[ ] Step 7 Pages serves X.Y.Z, verify-published-release ends OK
[ ] Step 8 optional production-feed update (only on maintainer request)
[ ] Step 9 post-release notes/docs/Pages check done, evidence reported
```

## 3. Step-by-step

### Step 0. Locate the inputs

1. Run `cat VERSION`, `git describe --tags --abbrev=0` and `git status --short`.
2. Success = status output is empty, and `VERSION` equals the latest tag without the `v` (the previous release). X.Y.Z is the NEXT version; you write it in Step 2.
3. STOP: if status is not empty, do not build. Report the dirty paths and ask what to do.

### Step 1. PR/CI gate

1. Run `gh pr checks <PR-number>` for the feature PR.
2. Success = every check says `pass` or `skipping`, none says `pending` or `fail`. (`main` has no required checks, so `gh pr merge` would merge immediately even with pending CI.) The "Cursor …" bot checks often stay `pending` for several minutes after the real CI jobs pass; they still count, so wait for them.
3. STOP: on any `pending`/`fail`, do not merge. Wait or fix, then re-run `gh pr checks <PR-number>`.
4. Merge with `gh pr merge <PR-number> --rebase --delete-branch`, then run `git checkout main && git pull --ff-only && git fetch --prune`.

### Step 2. Version bump

1. Write `X.Y.Z` into the `VERSION` file. Add a `## X.Y.Z - YYYY-MM-DD` section under `## Unreleased` in `CHANGELOG.md`. Nothing else gets bumped.
2. Run `git add VERSION CHANGELOG.md && git commit -m "Prepare X.Y.Z release notes and version"` (keep the `Co-Authored-By` trailer when present) `&& git push origin main`.
3. Success = push prints `main -> main`.
4. STOP: if the push is rejected, run `git pull --ff-only` and inspect; do not force-push. Ask the user.

### Step 3. Release build and log reading

1. Run `git checkout -- docs/appcast.xml` (a leftover modified appcast appends `-dirty` to the build ID).
2. Start the build DETACHED with a durable log, so a session restart or reboot cannot kill it (both happened):
   `mkdir -p ~/Library/Logs/apm44-release && nohup bash -c 'rm -rf build && bash scripts/release-all.sh; echo RELEASE_ALL_EXIT=$?' > ~/Library/Logs/apm44-release/release-X.Y.Z.log 2>&1 < /dev/null & disown`
3. Wait (about 10 min): `until grep -q RELEASE_ALL_EXIT= ~/Library/Logs/apm44-release/release-X.Y.Z.log; do sleep 15; done`.
4. Success = ALL hold for that log: the line `RELEASE_ALL_EXIT=0`; `grep -c '^[[:space:]]*status: Accepted' <log>` prints `3` (do NOT count every line containing "status: Accepted": notary progress lines contain it too, giving 6); one line `appcast signature: OK`; one line `build identity: X.Y.Z+<first 12 chars of git rev-parse HEAD>`.
5. Confirm outputs exist: `build/signing/APM44Bridge-X.Y.Z.pkg`, `build/signing/APM44Bridge-X.Y.Z.dmg` (each with `.sha256`), plus a modified `docs/appcast.xml`.
6. STOP: on any missing string or file, do not continue to E2E. Open `references/troubleshooting.md` (interrupted build, build-ID, dirty-appcast, notarization rows) and report.

### Step 4. E2E installed-update test with the candidate, BEFORE publishing

1. REQUIRED when `git diff --name-only v<previous>...HEAD` lists any path outside `VERSION`, `CHANGELOG.md`, `docs/appcast.xml`, `docs/*.md`. Otherwise OPTIONAL but recommended.
2. Never run an older candidate over a newer install. Compare first; STOP if the candidate is older.
3. This updates the REAL installed app and needs one human admin approval per run. Before starting, tell the user the "before E2E" sentence from section 4 and wait for a yes. Then run with `--yes`.
4. Run 1 (installer and the previous version's updater): `bash scripts/e2e-update-roundtrip.sh --pkg build/signing/APM44Bridge-X.Y.Z.pkg --expect-version X.Y.Z --start-bridge --yes 2>&1 | tee ~/Library/Logs/apm44-release/e2e-X.Y.Z-run1.log`. The installed app must be OLDER than X.Y.Z; STOP otherwise.
   - `--start-bridge` needs the selected output (AirPods Max over USB-C, awake) connected. If the script stops with `FAIL: the selected output (…) is not connected`, ask the user to plug in and put on the AirPods, then rerun; nothing was changed.
   - An installed app older than 0.12.15 has no automation hooks: the bridge checks print `NOT RUN` and the result says `PASS (all run checks passed; bridge checks NOT RUN …)`. That counts as a pass for run 1; run 2 covers the bridge checks.
5. Run 2 (the NEW app's own updater, log to `e2e-X.Y.Z-run2.log`), required when app update code changed (`App/APM44Bridge/SparkleUpdateController.swift`, `MenuContentView.swift`, `APM44BridgeApp.swift`): after run 1 passes, the Mac runs X.Y.Z. Re-offer the same package under a higher label: `bash scripts/e2e-update-roundtrip.sh --pkg build/signing/APM44Bridge-X.Y.Z.pkg --expect-version X.Y.Z --label 99.0.0 --start-bridge --yes`. Reinstalling the same version is allowed by the installer guard; the app stays X.Y.Z.
6. When the script prints its ACTION REQUIRED banner, tell the user the "admin prompt" sentence from section 4, then wait. Never type a password. Never click the prompt yourself.
7. Success = the final PASS/FAIL table shows `PASS` on every row.
8. STOP on any `FAIL`: do not publish. Open `references/troubleshooting.md` (E2E rows), save the table, and report. If the FAIL happened AFTER the update installed (installed version already X.Y.Z), do not rerun run 1 (the candidate is no longer newer); verify with run 2 instead.
9. Optional extra audio proof after a PASS: `bash scripts/e2e-check-audio-flow.sh --seconds 3`. Success = it reports flow OK.

### Step 5. Appcast commit, signed tag, publish

1. Run `git add docs/appcast.xml && git commit -m "Sign X.Y.Z Sparkle appcast" && git push origin main`.
2. Run `git -c gpg.format=ssh -c user.signingkey=$HOME/.ssh/id_ed25519.pub tag -s vX.Y.Z -m "APM44 Bridge X.Y.Z" && git push origin vX.Y.Z`.
3. Success = tag `vX.Y.Z` points at HEAD: `git rev-list -n 1 vX.Y.Z` equals `git rev-parse HEAD`.
4. STOP: if the tag is missing or not at HEAD, do not publish. Delete/recreate nothing; ask the user.
5. Run `SPARKLE_SIGN_UPDATE="$(bash scripts/ensure-sparkle-tools.sh)" bash scripts/publish-release.sh`.
6. Success = it prints `Release URL:` and `Published commit:`. It refuses when the tree is dirty, the tag is missing/not at HEAD, or the release exists.
7. STOP: on refusal, fix only what it names (commit, tag, or abort the duplicate), then re-run once.

### Step 6. Wait for Pages, then verify the published release

1. Run `until curl -s https://niko96-dotcom.github.io/apm44-bridge/appcast.xml | grep -q "<sparkle:shortVersionString>X.Y.Z"; do sleep 10; done` (usually 1-2 min; verifying immediately after publish fails on the stale feed).
2. Run `SPARKLE_SIGN_UPDATE="$(bash scripts/ensure-sparkle-tools.sh)" bash scripts/verify-published-release.sh`.
3. Success = last line is `verify-published-release: OK`.
4. STOP: on any other ending, do not claim the release. See `references/troubleshooting.md` (Pages-delay row), wait again, re-run once, then report.

### Step 7. Optional production-feed update on the maintainer's Mac

1. Only when the maintainer explicitly asks for real-world proof through the public feed. The app must be on the previous version (e.g. a machine that skipped the E2E test); otherwise there is nothing to update.
2. Trigger Check for Updates (the maintainer clicks it, or, when they asked you to drive it, System Events per `references/troubleshooting.md`), click Install, have the maintainer approve the admin prompt, and click Install and Relaunch.
3. Success = the app restarts at X.Y.Z; `bash scripts/e2e-check-audio-flow.sh --seconds 3` passes when the bridge runs.

### Step 8. Post-release

1. Save the release log and the E2E table somewhere durable (`/private/tmp` is wiped on reboot).
2. Check `https://niko96-dotcom.github.io/apm44-bridge/` loads and `docs/index.html` plus `docs/images/menu-bar-panel.png` are current (`docs/` on `main` serves Pages with `docs/.nojekyll`; Markdown is NOT rendered).
3. Report evidence using the template in section 5.

## 4. What to tell the user (exact sentences)

- Before starting the E2E test, say exactly: `I'm about to run the end-to-end update test: it reinstalls APM44 Bridge X.Y.Z on this Mac, briefly restarts the app and Core Audio, and needs one admin approval from you — may I start?`
- When the script prints its ACTION REQUIRED banner, say exactly: `Please approve the macOS administrator prompt for the APM44 Bridge update now (Touch ID or password); I cannot approve it for you and will wait.`
- When publishing needs approval, say exactly: `Please confirm I may publish APM44 Bridge version X.Y.Z now (with X.Y.Z filled in); I will not publish without your approval.`
- When E2E FAILs, say exactly: `The installed-update test failed; I stopped before publishing and saved the PASS/FAIL table for you to review.`

## 5. Evidence to report at the end (template)

```text
Version: X.Y.Z | HEAD: <sha> | tag vX.Y.Z at HEAD: yes/no
CI: <gh pr checks summary> | user publish approval: yes/no
Build: Accepted x3 yes/no | signature OK yes/no | identity X.Y.Z+<sha12> yes/no
E2E round trip: PASS/FAIL/NOT RUN (rows: <paste table>) | admin approval: human/auto(none)
Audio flow: PASS/FAIL/NOT RUN
Publish: Release URL <url> | commit <sha>
Verify-published: OK/failure output | Pages wait: <seconds>
Production-feed update: done/not requested
Caveats: <none or list>
```

Detail for every known failure: `references/troubleshooting.md`.
