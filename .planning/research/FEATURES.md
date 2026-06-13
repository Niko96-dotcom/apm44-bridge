# Feature Research

**Domain:** APM44 Bridge public-release safety fixes
**Researched:** 2026-06-13
**Confidence:** HIGH

## Feature Landscape

v0.6 is a blocker/fix milestone. The "features" are release-safety capabilities
that public users should be able to rely on without knowing the internals.

### Table Stakes

| Capability | Why Expected | Complexity | Repo Evidence |
|------------|--------------|------------|---------------|
| HAL mono-lane pairing rejects unrelated timestamp mismatches | Arbitrary left/right pairing can produce rare stereo skew, clicks, or comb filtering | HIGH | `flushPendingLanes()` falls through to `pushLanePair(left, right)` after unmatched mismatches. |
| HAL rollover pairing is explicit and narrow | Existing rollover test should remain valid without accepting every mismatch | MEDIUM | Test uses left `44032.0` with right `zeroTimestamp=44100.0`, `timestamp=0.0`. |
| Mixed-output processing respects IO stopped state | Lifecycle flag should defend against callbacks after stop | LOW | `ioRunning_` is set but not checked in `OnProcessMixedOutput()`. |
| Legacy AudioToolbox converter is not unsafe | Public CLI exposes `--legacy-converter`; debug paths still ship | MEDIUM | `InputDataProc` writes to `ioData->mBuffers[0].mData`; `inputInterleaved_` is allocated but unused as source. |
| DMG installer copies the app deterministically | Users expect app bundle install not to partially merge or fail with permissions | LOW | Generated command uses unprivileged `cp -R "$DIR/APM44 Bridge.app" /Applications/`. |
| Metrics publication avoids possibly-locking atomics in realtime path | Data-race-safe is not enough for realtime audio callback publication | MEDIUM | `MetricsPublisherState` stores three `std::atomic<double>` fields. |
| Device catalog refresh cannot deadlock on stderr | User device list refresh should not hang if child emits stderr | LOW | stdout is drained before wait; stderr is an undrained `Pipe()`. |
| Metrics stale timestamp resets at lifecycle boundaries | UI should not inherit stale timestamps across starts/idle transitions | LOW | `latestMetrics` and `metricsStale` reset, but `lastMetricsAt` does not. |
| GitHub CI runs release-script tests | Release hardening should not regress while badge stays green | LOW | `scripts/ci.sh` runs the tests; `.github/workflows/ci.yml` does not. |
| Drop-policy comments match drop-new behavior | Realtime policy should be clear to future maintainers | LOW | `pushInterleaved()` comment still says oldest is skipped. |

### Differentiators

| Capability | Value | Notes |
|------------|-------|-------|
| Timestamp pairing predicate named and tested | Makes the HAL rollover exception auditable | Prefer a small helper such as `SameLogicalLaneBlock`. |
| Source guards for release/RT invariants | Cheap protection for scripts/comments/atomics | Existing tests already use source-level guards in `test_hardening_audit.cpp` and release tests. |
| One release-safety CI lane | Local and GitHub gates become aligned | Add release-script tests after native tests. |

### Deferred

| Item | Reason |
|------|--------|
| Broad DAW compatibility matrix | Outside the nine concrete blockers. |
| PKG-primary public installer promotion | DMG command installer can be hardened now; PKG promotion needs separate UX/signing validation. |
| New DSP/resampler path | v0.6 should not replace the existing SRC architecture. |
| Hardware soak | Valuable but operator-dependent and not required to fix these code-level blockers. |

## Scope Recommendation

Capture all nine audit items in v0.6 requirements. The first HAL item should be
split into explicit sub-requirements because it is the highest-risk item:

- reject unrelated mono-lane mismatches,
- preserve only named rollover pairing,
- add regression coverage for normal, mismatch, and rollover cases.

The legacy converter requirement should be worded as outcome-based: the public
build either no longer exposes the flag, or the converter callback uses owned
input storage with regression coverage.

## Regression Expectations

| Capability | Expected Test Type |
|------------|--------------------|
| HAL arbitrary mismatch rejection | Catch2 behavior test using `ShmIoHandler` and `MmapShmRing`. |
| HAL rollover allowance | Existing rollover test updated to exercise named predicate behavior. |
| `ioRunning_` guard | Catch2 test that stops IO then calls `OnProcessMixedOutput()` and observes no frames. |
| Legacy converter safety | Catch2 converter test plus source guard that callback no longer writes into Core Audio-provided input storage. |
| Metrics lock-free storage | Compile-time static assertions and source/test guard against `std::atomic<double>`. |
| DeviceCatalog stderr | Swift/source guard for `FileHandle.nullDevice` or concurrent stderr drain. |
| `lastMetricsAt` reset | Swift lifecycle test or narrow testing accessor. |
| DMG installer app copy | Release script source test for `sudo rm -rf`, `sudo ditto`, and `sudo chown`. |
| GitHub CI release tests | Release script source test for `bash tests/test_release_scripts.sh` in `.github/workflows/ci.yml`. |
| Drop comment | Source guard or direct comment update. |

---
*Feature research for: APM44 Bridge v0.6 Public Release Safety Fixes*
*Researched: 2026-06-13*
