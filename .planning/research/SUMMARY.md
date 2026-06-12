# Project Research Summary

**Project:** APM44 Bridge
**Domain:** macOS audio bridge public-release hardening
**Researched:** 2026-06-12
**Confidence:** HIGH

## Executive Summary

v0.4 should be treated as a release-blocker closure milestone, not a new feature milestone. The attached review and source scan identify concrete correctness and trust boundaries that should be resolved before publishing: metrics publication must be standards-compliant under C++, JSON serialization must not read beyond fixed buffers, Core Audio edge/error paths must fail safely, and release automation must not silently publish unsigned or unnotarized artifacts.

The recommended approach is to keep the implementation tightly scoped to the existing repo seams: `MetricsPublisher`, `BridgeMetrics::ToJsonLine`, `IoProcHandlers`, `BridgeEngine::start`, release shell scripts, GitHub workflows, and public docs. Apple and GitHub official guidance reinforce two release themes: use Developer ID/notarization/stapling as a strict artifact gate, and harden workflows near secrets/artifacts with immutable action references or explicit trust decisions.

The main risk is false confidence. Several current paths look "done" in ordinary cases but fail under adversarial or edge conditions: a seqlock stress test can pass while the C++ payload access is still a data race, notary scripts can accept everything except `Invalid`, and release commands can print artifacts after skipping notarization. v0.4 should make these failure modes boring, explicit, and testable.

## Key Findings

### Recommended Stack

Keep the existing stack: C++20, Catch2, XCTest, shell release scripts, GitHub Actions, and Apple Developer ID tools. Add or expose a ThreadSanitizer-oriented native metrics proof using Clang/Xcode's `-fsanitize=thread` where practical.

**Core technologies:**
- C++20 atomics: race-free metrics publication without locks in realtime paths.
- Clang ThreadSanitizer: test-only dynamic data-race detection on Darwin.
- Apple `notarytool`/`stapler`: strict notarization and ticket validation for ZIP/PKG/DMG artifacts.
- GitHub Actions full SHA pins: preferred immutable references for critical workflow dependencies.

### Expected Features

**Must have (table stakes):**
- Race-free metrics publisher.
- Safe JSON truncation behavior.
- Core Audio virtual-device output-start failure cleanup.
- Non-interleaved input min-buffer sizing.
- Fail-closed notarization and release scripts.
- Strict signing workflow with no masked app-build failure.
- Public local IPC threat model for `0666` shm.
- Regression tests for every blocker.

**Should have (competitive):**
- Signed PKG installer direction for a HAL driver.
- Stapled inner app/driver artifacts before final DMG/PKG validation.
- SHA-pinned critical release workflow actions or explicit exception record.
- Mocked release-script failure matrix in CI.

**Defer (v0.5+):**
- Logic/Ableton compatibility matrix.
- Support bundle export.
- Per-user/group-owned shm or XPC-mediated IPC setup.
- New DSP/resampler architecture.

### Architecture Approach

Use four focused implementation lanes: runtime correctness, release automation, public distribution/security posture, and final validation. Runtime fixes should land first because release validation is not meaningful while undefined behavior and callback overread risks remain. Release automation comes next so every later artifact proof is fail-closed. Public docs/installer decisions come after the scripts are strict, then final validation records a clean release command sequence.

**Major components:**
1. Runtime correctness layer - `MetricsPublisher`, `BridgeMetrics`, `IoProcHandlers`, `BridgeEngine`.
2. Release automation layer - `notarize-release-dmg.sh`, `notarize-release-pkg.sh`, `release-all.sh`, `sign-notarize.yml`.
3. Public distribution layer - release/install/HAL docs, DMG/PKG decision, local IPC threat model.
4. Validation layer - CI, TSan/local proof, mocked script tests, codesign/stapler/spctl checks.

### Critical Pitfalls

1. **Seqlock around a plain payload** - replace with atomic fields or a buffer scheme that avoids concurrent non-atomic access.
2. **`snprintf` truncation overread** - reject or reallocate on `written >= sizeof(buffer)`.
3. **Virtual-mode cleanup using non-created input IOProc** - guard cleanup by mode and non-null IOProc.
4. **Non-interleaved input buffer mismatch** - use the minimum frame count across channel buffers.
5. **Notary status masking** - require return code 0 and `status: Accepted`, not merely "not Invalid".
6. **Silent unnotarized release artifact** - hard fail unless explicit local-only override is set.
7. **Undocumented world-writable shm** - explain local IPC assumptions and non-boundary.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 13: Runtime Correctness Blockers
**Rationale:** Undefined behavior and callback overread risks undermine any release proof.
**Delivers:** Metrics race fix, JSON truncation fix, virtual cleanup guard, input min-frame clamp, helper rename/dead helper cleanup.
**Addresses:** metrics, JSON, Core Audio error paths, realtime helper clarity.
**Avoids:** TSan false confidence and edge-case Core Audio failures.

### Phase 14: Release Automation Fail-Closed
**Rationale:** Public artifacts must not be generated by permissive scripts.
**Delivers:** Strict notary parsing, missing-profile hard failure with explicit override, workflow build failure unmasked, shell tests with mocked `xcrun`.
**Uses:** Apple notarytool/stapler, existing scripts, GitHub Actions workflow.
**Avoids:** unnotarized or stale artifacts that look releasable.

### Phase 15: Public Distribution UX and Security Posture
**Rationale:** A professional release must explain install/security assumptions and converge on DMG/PKG behavior.
**Delivers:** Local IPC threat model, DMG/stapling order decision, signed PKG direction, workflow pinning/trust decision.
**Implements:** public docs and release UX changes.
**Avoids:** hidden `0666` shm assumptions and installer trust gaps.

### Phase 16: Release Validation Closure
**Rationale:** Final proof should validate the exact artifact path after the scripts and docs are strict.
**Delivers:** Clean validation run, release checklist, documented live/hardware blockers if any remain.
**Implements:** final command sequence from secret scan through Gatekeeper assessment.

### Phase Ordering Rationale

- Runtime UB and callback safety come first because release automation cannot prove a broken runtime safe.
- Release scripts come before docs finalization so public docs match actual command behavior.
- Distribution/security posture comes before final validation so validation covers the chosen artifact and trust model.
- Final validation is last so it can exercise all blocker fixes together.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 13:** exact metrics representation tradeoff - atomic fields vs triple buffer.
- **Phase 14:** shell-test harness pattern for mocked `xcrun` without new dependencies.
- **Phase 15:** whether signed PKG becomes primary artifact or explicitly documented next-release direction.

Phases with standard patterns:
- **Phase 13 JSON/callback fixes:** straightforward local source changes and tests.
- **Phase 14 workflow `|| true` removal:** straightforward.
- **Phase 16 validation:** existing scripts already provide most commands.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Existing repo stack is sufficient; official docs confirm TSan, notarytool/stapler, and SHA-pinning practices. |
| Features | HIGH | Derived from attached blocker review and confirmed against source/workflows. |
| Architecture | HIGH | Integration points are narrow and present in current repo. |
| Pitfalls | HIGH | Each major pitfall maps to a concrete code/script/doc location. |

**Overall confidence:** HIGH

### Gaps to Address

- **Metrics design choice:** Decide atomic fields vs triple buffer during Phase 13 planning.
- **TSan availability in CI:** If GitHub macOS runner cannot reliably run TSan for this project, require a documented local TSan command plus source-level guard.
- **PKG primary artifact:** Decide in Phase 15 whether v0.4 ships PKG-primary or documents it as the next release track.
- **Apple credentials:** Live notarization still depends on maintainer keychain/cert availability; mocked tests should cover logic without credentials.

## Sources

### Primary (HIGH confidence)

- https://clang.llvm.org/docs/ThreadSanitizer.html - ThreadSanitizer purpose, Darwin support, usage, and non-production runtime note.
- https://developer.apple.com/developer-id/ - Developer ID signing, notarytool, stapler, and ZIP/PKG/DMG support.
- https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution - signed installer package expectation.
- https://docs.github.com/en/actions/reference/security/secure-use - full-length commit SHA pinning and GitHub Actions security guidance.
- APM44 Bridge source/workflow scan on 2026-06-12.

### Secondary (MEDIUM confidence)

- Attached "Blockers before publishing" review, 2026-06-12 - scoped blocker list and suggested tests.

---
*Research completed: 2026-06-12*
*Ready for roadmap: yes*
