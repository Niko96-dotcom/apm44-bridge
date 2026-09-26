# APM44 release troubleshooting

Each row: symptom → cause → exact fix. Stop the release sequence; fix; re-run only the named step.

## PR merged with pending or failing CI

- Symptom: `gh pr checks <n>` showed `pending`, but the PR is already merged; CI later fails (observed: a timing test failed after a 0.12.10 merge).
- Cause: `main` has no required status checks, so `gh pr merge` merges immediately even while CI is pending.
- Fix: never merge unless every check is `pass` or `skipping`. Repair on `main` with a follow-up PR, get it green, then rebuild from the new HEAD.

## Build ID changed after an extra commit

- Symptom: release log `build identity:` shows a different `+<12-char SHA>` than the HEAD the build started from.
- Cause: the build ID is `<VERSION>+<first 12 chars of the last commit SHA touching anything except docs/appcast.xml>`. Any other commit after the build starts changes the ID.
- Fix: run `git rev-parse HEAD`, then `rm -rf build && bash scripts/release-all.sh` again so the build matches the new HEAD.

## Dirty appcast makes the build dirty

- Symptom: build identity ends in `-dirty` although `git status --short` looked clean before.
- Cause: a modified `docs/appcast.xml` left over from a previous build dirties the worktree; a dirty worktree appends `-dirty`.
- Fix: run `git checkout -- docs/appcast.xml` first, then `rm -rf build && bash scripts/release-all.sh`.

## Reboot wiped /tmp mid-release

- Symptom: a background command fails instantly with `no such file`; the scratchpad under `/private/tmp` is gone.
- Cause: the session scratchpad `/private/tmp` is wiped on reboot.
- Fix: recreate the directory, rerun the failed command, and keep release logs plus the E2E table somewhere durable.

## Verify fails right after publishing (Pages delay)

- Symptom: `bash scripts/verify-published-release.sh` fails within seconds of a successful `bash scripts/publish-release.sh`.
- Cause: GitHub Pages needs 1–2 min before the hosted appcast serves the new version.
- Fix: run `until curl -s https://niko96-dotcom.github.io/apm44-bridge/appcast.xml | grep -q "<sparkle:shortVersionString>X.Y.Z"; do sleep 10; done`, then `SPARKLE_SIGN_UPDATE="$(bash scripts/ensure-sparkle-tools.sh)" bash scripts/verify-published-release.sh` again. Success ends `verify-published-release: OK`.

## Install wiped everything or app landed in the wrong place

- Symptom: after running a PKG, `/Applications/APM44 Bridge.app` is gone or a copy inside the repo (e.g. `build/Release`) was updated instead of `/Applications`.
- Cause: PKGs from 0.12.11 and earlier run an unconditional `rm -rf` preinstall while PackageKit skips version-checked components on downgrade (stale older download deletes everything, installs nothing); without `BundleIsRelocatable=false`, PackageKit relocates into another same-bundle-id copy.
- Fix: never run an old PKG over a newer install. Recover: move Spotlight-indexed copies out of indexed paths (e.g. into a folder named `*.noindex`), run `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u <stale-path>`, confirm `mdfind "kMDItemCFBundleIdentifier == 'com.niko.apm44.menu'"` lists only `/Applications/APM44 Bridge.app`, then run the latest PKG.

## Sparkle ready window never seen (hidden behind other apps)

- Symptom: the update stalls after the admin prompt; hours later the Install-and-Relaunch window is found behind other apps.
- Cause: the accessory app has no Dock presence, so Sparkle windows open unseen (observed: 7 h stall).
- Fix: current releases bring the window forward automatically. If it stalls, bring `APM44 Bridge` forward manually and look for its Dock icon; do not re-run the installer. Report the stall with timestamps.

## False "update failed" (SUSparkleErrorDomain 4005)

- Symptom: right after a successful install, the app shows an update-failed alert although the new version is installed.
- Cause (old): the postinstall `open` raced Sparkle's own relaunch. Fixed releases skip the `open` for Sparkle-staged packages.
- Fix: check `/Applications/APM44 Bridge.app` version first. If it equals the expected version, this is the stale false 4005: dismiss the alert and report it. If versions differ, treat as a real failure.

## Audio device IDs renumbered

- Symptom: `say -a <id>` or an audio check fails with a device id that worked minutes ago.
- Cause: the APM44 Bridge device id changes after every `coreaudiod` reload (observed `106→112→120` in one session).
- Fix: re-run `say -a '?'`, resolve the current id every time, and re-run `bash scripts/e2e-check-audio-flow.sh --seconds 3`.

## Notarization failure

- Symptom: `bash scripts/release-all.sh` exits at the notarize step; no `status: Accepted` lines.
- Cause: missing/unusable notary profile or an Apple-side rejection.
- Fix (NOT RUN guidance): do not retry blindly and do not publish. Record `NOT RUN` for notarize/staple/publish gates, save the submission id, fetch `xcrun notarytool log <submission-id> --keychain-profile "AC_NOTARY" notary-log.json`, and hand the log to the maintainer. Never set `APM44_ALLOW_UNNOTARIZED=1` for a public release (local-only artifacts must never publish).

## Admin prompt never answered (E2E timeout)

- Symptom: `bash scripts/e2e-update-roundtrip.sh` waits, then times out at the authorization wait.
- Cause: only the human can approve the macOS admin prompt; nobody approved it in time.
- Fix: re-run `bash scripts/e2e-update-roundtrip.sh --pkg build/signing/APM44Bridge-X.Y.Z.pkg --expect-version X.Y.Z` with the human present, deliver the section-4 sentence when the banner prints, and wait.

## Isolated dev app behaves differently

- Symptom: a UI experiment does not reproduce installed-app behavior (no updates, different prefs).
- Cause: `bash scripts/rebuild-and-open-app.sh --isolated` uses its own bundle id and defaults, loopback feed, and sets `SUEnableAutomaticChecks` false, leaving the installed app alone.
- Fix: use `--isolated` only for UI experiments without Start/driver/login changes. Stop it with `bash scripts/rebuild-and-open-app.sh --isolated-stop`. Release E2E must use the real installed app plus `scripts/e2e-update-roundtrip.sh`, never the isolated app.

## Dev build Start blocked by build-ID mismatch

- Symptom: pressing Start in a dev build is blocked although the installed release works.
- Cause: dev builds get a new git-SHA build ID that does not match the installed release driver. That is expected, not a bug.
- Fix: do nothing to the release. Test Start only after the E2E round trip installs matching app and driver, or via `bash scripts/e2e-check-audio-flow.sh --seconds 3`.

## Preinstall/postinstall guard test (manual block, coordinator resolves path)

- Symptom: need to verify the installer downgrade guard without touching the real install.
- Cause: running the real preinstall kills the running app and deletes the real install.
- Fix: never run the real scripts. Verify the guard only with the guard-only mode:

```bash
# The guard matrix (newer app/driver refused, equal/older/missing allowed, unparseable refused) is covered by:
bash tests/test_release_scripts.sh      # success: last line "release script tests: OK"
# To check the guard inside a built candidate by hand, extract the package and run ONLY the guard:
rm -rf /tmp/apm44-pkgx && pkgutil --expand build/signing/APM44Bridge-X.Y.Z.pkg /tmp/apm44-pkgx
APM44_PREINSTALL_GUARD_ONLY=1 /bin/bash /tmp/apm44-pkgx/Scripts/preinstall pkg / /
# Success: exit 0 when the installed version is <= X.Y.Z; exit 1 with "refusing to replace it with older" when newer.
# STOP: never run that script without APM44_PREINSTALL_GUARD_ONLY=1.
```
