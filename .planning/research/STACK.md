# Stack Research

**Domain:** macOS audio bridge public-release hardening
**Researched:** 2026-06-12
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| C++20 atomics | current repo standard | Race-free metrics publication | The existing seqlock wraps a plain `MetricsSnapshot`; v0.4 should publish each shared field atomically or use a buffer ownership scheme that prevents concurrent non-atomic access. |
| `std::atomic<uint64_t>` + bit-cast double storage | C++20 | Atomic representation for double metrics | Keeps CLI/UI metrics available without locking the realtime path. Store counters as atomics directly and floating fields as bit patterns. |
| Clang ThreadSanitizer | Xcode/LLVM toolchain, `-fsanitize=thread` | Dynamic race detection | LLVM documents ThreadSanitizer as a data-race detector supported on Darwin arm64/x86_64. Use it for tests only, not production binaries. |
| Catch2 | existing native test stack | C++ regression coverage | Already used by this repo for ring, callback, shm, metrics, and script-adjacent guards. |
| XCTest | existing Swift test stack | App/process lifecycle regression coverage | Already verifies process manager and UI-adjacent state behavior. Keep using it for app workflow checks. |
| `xcrun notarytool` + `xcrun stapler` | Xcode 14+ path | Developer ID notarization and ticket stapling | Apple supports custom workflows through `notarytool`; notarized artifacts receive tickets that Gatekeeper can evaluate. |
| `codesign`, `pkgbuild`, `productsign`, `spctl`, `pkgutil` | Xcode/macOS tools | Release signing, installer construction, and assessment | Required for professional app/driver/PKG/DMG distribution validation. |
| GitHub Actions pinned by commit SHA | GitHub-hosted workflow model | CI/release supply-chain hardening | GitHub states full-length commit SHAs are the immutable action reference option. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Existing `MetricsPublisher` wrapper | repo-local | Single integration point for metrics publication | Replace its internals while preserving `BridgeEngine` call sites. |
| Existing shell scripts under `scripts/` | repo-local | Release automation | Patch scripts rather than adding a second release path. |
| Mock shell harness or lightweight fixture scripts | repo-local | Test notary/release failure cases | Use for `notarytool` output variants, missing credentials, and explicit unnotarized override checks. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `cmake`/`ctest` | Native build and tests | Add a TSan-capable build target or documented local command for metrics tests. |
| `xcodebuild test` | Swift app tests | Keep as part of `scripts/ci.sh`. |
| `bash scripts/ci.sh` | Repo gate | Should include non-hardware release-script checks where possible. |
| `bash scripts/verify-app-build.sh` | App artifact gate | Must not be masked in signing/notarization workflows. |
| `bash scripts/release-all.sh` | Maintainer release command | Should fail when notarization credentials are missing unless an explicit opt-out is set. |

## Installation

No new runtime dependency is required. v0.4 should use the existing repo stack:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --parallel 4
ctest --test-dir build --output-on-failure

# TSan-capable local proof, exact CMake switch to be defined during implementation.
cmake -S . -B build-tsan -DCMAKE_BUILD_TYPE=Debug -DAPM44_ENABLE_TSAN=1
cmake --build build-tsan --parallel 4
ctest --test-dir build-tsan --output-on-failure -R Metrics
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Atomic field publication | Seqlock around plain struct copy | Do not use for cross-thread non-atomic payloads; it is not data-race safe in standard C++. |
| Atomic bit-cast doubles | Mutex-protected metrics snapshot | Use a mutex only outside realtime paths; avoid it where an audio callback can publish. |
| Explicit fail-closed notary scripts | Grep only for `status: Invalid` | Do not use for release commands; misses auth, network, malformed output, and non-Accepted states. |
| Signed/notarized PKG direction | DMG with `.command` installer only | DMG can remain an artifact, but HAL driver install UX should prefer a proper signed installer path. |
| Full-length SHA pins | Major tags like `actions/checkout@v6` | Tags are acceptable only with a documented trust decision; release/signing workflows should prefer SHA pins. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Plain `MetricsSnapshot` shared under seqlock | Reader and writer still access non-atomic fields concurrently | Atomic field representation or proven buffer handoff. |
| `std::string(buffer, written)` after truncated `snprintf` | `snprintf` returns the would-have-written size, which can exceed the stack buffer | Return `{}` or allocate a correctly sized string after detecting truncation. |
| `|| true` in signing/release workflows | Masks app build failures near credentials and artifacts | Fail the job, or require an explicit manual skip variable. |
| Silent unnotarized release path | Produces artifacts that can look publishable but are not public-release ready | Hard fail unless `APM44_ALLOW_UNNOTARIZED=1` or equivalent is set. |
| Undocumented world-writable shm | Looks like a security boundary while local users/processes can interfere | Document local IPC assumptions and future hardening options. |

## Stack Patterns by Variant

**If publishing a public DMG remains primary:**
- Staple inner `.app` and `.driver` before final DMG construction where possible.
- Notarize and staple the final DMG.
- Validate app, driver, and DMG with `codesign`, `stapler`, and `spctl`.

**If moving to PKG-primary install UX:**
- Keep app signed with Developer ID Application.
- Sign the installer package with Developer ID Installer.
- Notarize and staple the PKG.
- Keep DMG either as a container for the PKG or as a secondary artifact.

**If GitHub signing/notarization stays manual:**
- Keep workflow dispatch.
- Fail hard when prerequisites are missing.
- Make "local only, unsigned/unnotarized" an explicit opt-in path, never the default release command.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| ThreadSanitizer | Darwin arm64/x86_64 | LLVM documents support on Darwin; use only in test binaries. |
| Apple notarization | Xcode 14+ `notarytool` | Apple stopped accepting `altool`/older Xcode uploads on 2023-11-01. |
| GitHub Actions | Full-length action SHA pins | GitHub documents SHA pinning as the immutable action reference model. |

## Sources

- https://clang.llvm.org/docs/ThreadSanitizer.html - TSan support, usage, and non-production runtime note.
- https://developer.apple.com/developer-id/ - Developer ID signing, notarytool, stapler, ZIP/PKG/DMG support.
- https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution - Installer package signing expectation.
- https://docs.github.com/en/actions/reference/security/secure-use - GitHub Actions SHA-pinning and workflow security guidance.
- Repo source scan: `MetricsPublisher.h`, `BridgeMetrics.cpp`, `BridgeEngine.cpp`, `IoProcHandlers.cpp`, `scripts/*`, `.github/workflows/*`.

---
*Stack research for: APM44 Bridge v0.4 Public Release Blocker Closure*
*Researched: 2026-06-12*
