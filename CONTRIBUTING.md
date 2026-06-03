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
bar app when XcodeGen is available.

## Real-Time Audio Rules

The bridge and HAL paths have a stricter bar than ordinary app code.

Do not add these operations to audio callbacks or HAL I/O paths:

- allocation or deallocation
- mutexes, condition variables, or blocking waits
- logging, printing, file I/O, or device enumeration
- Swift ARC, Objective-C messaging, or UI mutation

Keep audio callbacks boring: copy data, touch preallocated buffers, update
lock-free counters, and return.

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
