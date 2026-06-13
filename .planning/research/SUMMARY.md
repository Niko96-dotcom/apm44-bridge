# Project Research Summary

**Project:** APM44 Bridge
**Domain:** Public-release safety fixes
**Researched:** 2026-06-13
**Confidence:** HIGH

## Executive Summary

v0.6 should be a narrow public-release safety milestone. The repo scan confirms
all nine audit items still map to live code or workflow surfaces: HAL mono-lane
pairing can still pair arbitrary timestamp mismatches, `ioRunning_` is not
enforced in the hot path, the debug AudioToolbox converter callback writes into
unknown input storage, the DMG command installer copies the app with
unprivileged `cp -R`, metrics use `std::atomic<double>`, `DeviceCatalog` leaves
stderr as an undrained pipe, `lastMetricsAt` is not reset with metrics state,
GitHub CI omits release-script tests, and the `pushInterleaved()` comment still
describes the wrong drop policy.

The highest-risk item is HAL timestamp pairing. Fixing it requires a small data
model change, not just a condition tweak: `PendingLaneBlock` must carry
`zeroTimestamp` so rollover can be a named, narrow predicate based on logical
absolute time. Once that is in place, arbitrary mismatches should fail closed by
dropping the older logical lane.

The rest of the milestone is smaller but release-important. The safest plan is
to split v0.6 into runtime/HAL safety, converter/metrics realtime safety,
app/release automation hardening, and final regression closure.

## Key Findings

### Runtime and HAL

- `ShmIoHandler::OnProcessMixedOutput()` ignores `zeroTimestamp` and passes only
  `timestamp` into pending mono-lane state.
- `PendingLaneBlock` stores `sampleTime` but not `zeroTimestamp`.
- `flushPendingLanes()` searches ahead for exact timestamp matches, but if none
  is found it still pushes the mismatched left/right pair.
- Existing tests cover normal mono pairing, rollover pairing, dropping stale
  repeated lanes, queued repeated lanes, and null-stream mono ignore; they do
  not cover unrelated mismatch rejection or stopped-IO rejection.
- `pushInterleaved()` comment still says oldest data is implicitly skipped,
  contradicting the project drop-new/input-tail policy.

### Converter and Metrics

- `--legacy-converter` remains public CLI/debug surface and is documented in
  `docs/soak-test.md`.
- `AudioConverterSrc::InputDataProc()` writes interleaved samples into
  `ioData->mBuffers[0].mData`; `inputInterleaved_` exists but is not used as
  callback source storage.
- `MetricsPublisherState` uses `std::atomic<double>` for `fillMs`,
  `smoothedRatio`, and `ppm`. This is data-race-safe but lacks a portable
  lock-free realtime guarantee.
- Existing metrics tests already stress the seqlock and source-guard bare
  `MetricsSnapshot` copies; they can be extended to guard double storage.

### Swift App and Release Automation

- `DeviceCatalog.refresh()` correctly drains stdout before waiting, but stderr
  is still an unread `Pipe()`. `FileHandle.nullDevice` is the smallest safe fix.
- `BridgeProcessManager.start()` resets `latestMetrics`, `lastXrunCount`, and
  `metricsStale`, but not `lastMetricsAt`. `transitionToIdle()` also leaves
  metrics timestamp state intact.
- `scripts/build-release-dmg.sh` generated installer uses deterministic sudo
  `ditto` for the HAL driver, then unprivileged `cp -R` for the app bundle.
- Local `scripts/ci.sh` runs `tests/test_release_scripts.sh`; GitHub CI does not.

## Recommended Requirements Shape

Use ten requirements rather than nine so HAL pairing is explicit:

1. HAL rejects unrelated mono-lane timestamp mismatches.
2. HAL preserves rollover pairing only through a named narrow predicate.
3. HAL ignores mixed-output callbacks while IO is stopped.
4. Legacy converter is either removed from public build or fixed to use owned
   input buffers.
5. DMG command installer replaces the app bundle deterministically with sudo
   `ditto`.
6. Metrics publisher stores floating payloads with a lock-free realtime-safe
   representation.
7. Device catalog refresh cannot block on stderr.
8. Metrics timestamp state resets on start and idle transitions.
9. GitHub CI runs release-script tests.
10. HAL drop-policy comments match drop-new behavior.

## Suggested Roadmap

Because v0.5 ended at Phase 22, continue numbering:

| Phase | Name | Goal | Requirement Focus |
|-------|------|------|-------------------|
| 23 | HAL Runtime Pairing Safety | Make HAL output fail closed for timestamp mismatch and stopped IO | HAL pairing, rollover, ioRunning, comment |
| 24 | Realtime Converter and Metrics Safety | Remove unsafe debug converter behavior and make metrics payload storage RT-safe | legacy converter, metrics atomics |
| 25 | App and Release Automation Reliability | Harden app lifecycle/catalog edges and release/install CI gates | DMG installer, DeviceCatalog, lastMetricsAt, GitHub CI |
| 26 | Regression and Release Safety Closure | Reconcile all tests and evidence before v0.6 close | full local gate and traceability |

## Open Decisions

| Decision | Recommendation | Reason |
|----------|----------------|--------|
| Fix or remove `--legacy-converter` | Fix if preserving debug comparison is still useful; remove if public surface minimization wins | Both are acceptable, but the requirement should demand one safe outcome. |
| Rollover tolerance value | Start with 128 frames | Current rollover test differs by 68 frames; 128 is narrow but leaves margin. |
| DeviceCatalog stderr behavior | Discard stderr | The app already reports a generic device-list failure; diagnostics are not used. |
| Metrics double storage | Bit-pack into `atomic<uint64_t>` | More portable realtime guarantee than `atomic<double>`. |

## Validation Commands

Expected phase and milestone validation should include:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure
bash tests/test_release_scripts.sh
xcodebuild -project App/APM44Bridge.xcodeproj \
  -scheme APM44Bridge \
  -destination 'platform=macOS' \
  -derivedDataPath build/app \
  test -only-testing:APM44BridgeTests \
  CODE_SIGNING_ALLOWED=NO
gsd-sdk query state.validate
gsd-sdk query roadmap.analyze
```

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| HAL pairing diagnosis | HIGH | Direct source/test evidence confirms fallback behavior. |
| IO running guard | HIGH | Single obvious guard and direct regression. |
| Legacy converter safety | HIGH | Callback writes to `ioData` storage; fix shape is clear. |
| Metrics atomics | HIGH | Source clearly uses `atomic<double>`; bit-pack fix is local. |
| Swift app fixes | MEDIUM | Implementation is simple; private `lastMetricsAt` may need a small test hook. |
| Release script/CI fixes | HIGH | Script/workflow locations are direct and existing tests are extensible. |

---
*Research summary for: APM44 Bridge v0.6 Public Release Safety Fixes*
*Researched: 2026-06-13*
