# Contributing

Thanks for helping make APM44 Bridge reliable for real DAW sessions.

## Development Setup

Requirements:

- macOS 14 or newer
- Xcode 16.x, or Xcode 15.4+
- CMake 3.28+
- XcodeGen

Clone with submodules:

```bash
git clone --recurse-submodules https://github.com/Niko96-dotcom/apm44-bridge.git
cd apm44-bridge
git submodule update --init --recursive
```

Build and test:

```bash
bash scripts/ci.sh
```

The CI script configures CMake, builds the daemon, driver, shared code, and
tests, runs `ctest`, runs the repo secret check, and verifies the Swift menu
bar app. XcodeGen is required unless `APM44_SKIP_APP=1` explicitly requests
native-only verification.

See [Local verification and performance](docs/development-verification.md)
for isolated UI launch, fresh worktrees, benchmarks, sanitizer commands, and
the opt-in Xcode 26.6 compiler-probe workaround exercised on the development Mac.

## Real-Time Audio Rules

The bridge and HAL paths have a stricter bar than ordinary app code.

Do not add these operations to audio callbacks or HAL I/O paths:

- allocation or deallocation
- mutexes, condition variables, or blocking waits
- logging, printing, file I/O, or device enumeration
- Swift ARC, Objective-C messaging, or UI mutation

Keep audio callbacks boring: copy data, touch preallocated buffers, update
lock-free counters, and return.

## Test Rules

A test earns its place by failing when the behavior it names breaks. The
2026-09 test audit removed tests that could not fail; keep them out:

- Test behavior, not source text. Do not read or grep a source file as a
  stand-in for running the code. Call the function, run the script, or drive
  the state and assert the result.
- No placeholders. No `SUCCEED()`, `XCTAssertTrue(true)`, or empty test bodies.
  Every test asserts a specific output.
- Fake `kill` with a `BASH_ENV` shim that defines a `kill()` function, as
  `tests/test_rebuild_and_open_app.sh` does. Bash's builtin `kill` bypasses a
  fake `kill` on `PATH`, so a PATH fake lets the test signal real processes.
- Inject dependencies through small interfaces passed to `init` (for example
  `ProcessLaunching`). Do not add new `…ForTesting` members or mutable
  override properties to production types.
- Measure Swift coverage per test when comparing before and after. The Swift
  tests run hosted in the app, and app launch enumerates audio devices, so the
  total coverage number changes with which devices are connected.

Before adding a test, check that it fails when you break the code it covers.

## Pull Requests

Before opening a PR:

```bash
bash scripts/check-secrets.sh
bash scripts/ci.sh
```

For changes that touch routing, device formats, signing, or packaging, update
the matching document in `docs/` and include verification notes in the PR.

## Release Changes

Release signing and notarization are intentionally environment-driven. Do not
commit Apple Developer identities, App Store Connect key IDs, issuer IDs,
private keys, certificates, passwords, or notarization logs.

Use:

```bash
export SIGN_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="AC_NOTARY"
bash scripts/release-all.sh
```

See `docs/release.md` for the full release checklist.
