---
quick_id: 260601-r4p
slug: menu-bar-popover-refresh
status: complete
date: 2026-06-01
commit: cd29a15
---

# Quick Task 260601-r4p — Summary

## What changed

Fuller visual refresh of the menu bar popover (view layer only). Direction
chosen by user: full refresh, not just bug fixes.

**Files:**
- `App/APM44Bridge/MenuContentView.swift` — rebuilt layout.
- `App/APM44Bridge/LatencyPreset.swift` — added additive `shortTitle` and
  `targetDescription` computed properties (no change to `targetFillMs`).

**New layout (top → bottom):**
1. **Status hero** — status icon in a state-tinted circle, connection phase as
   the title, routing-mode label as subtitle, and a live `~N ms` latency capsule
   badge (trailing) when running. Tint: gray idle / orange starting+waiting /
   green connected+running / red error.
2. **Routing-flow strip** — `routingMode.detail` in a subtle rounded container.
3. **Grouped control card** — Output / Latency / Quality as consistent
   icon-labeled rows (`hifispeaker.fill`, `speedometer`, `waveform.path`) inside
   a faint rounded card.
   - Latency segmented control now uses short labels (`Low`/`Balanced`/`Safe`)
     with a dynamic `~N ms buffer target` line beneath — **fixes the clipping**.
   - Output picker gains a `Choose output…` placeholder when nothing is selected;
     empty state has a `speaker.slash` icon + guidance.
4. **Primary button** — full-width `.large` Start/Stop with play/stop icons.
5. **Detail block** — running: buffer-fill bar + ms, Glitches (with pulsing
   `symbolEffect` flash, reduce-motion aware) and Drift ratio stats, stale note.
   Idle: `Monitoring adds latency` demoted from `.title3` to a small info row
   (message preserved — project forbids "zero latency" copy).
6. **Footer** — Open-at-login switch, version, Cubase setup link.

Window widened 320 → 340.

## Behavior preserved (view-layer-only change)
All bindings unchanged: `outputSelection`, `srcQualityBinding`, latency
`onChange` (`onPresetChanged` + `restartIfRunning`), `primaryButton`/`canStart`,
`openAtLoginBinding`, banner, Cubase link, accessibility labels, glitch
`symbolEffect`, `reduceMotion`.

## Verification
- `bash scripts/verify-app-build.sh` → **BUILD SUCCEEDED**.
- Static guards: no prohibited latency copy; `return 8/15/30` intact;
  `--metrics-json` intact.
- `LatencyPresetTests` assertions all reference untouched values (additive
  change only).

## Known issue (pre-existing, NOT from this task)
`xcodebuild ... test -only-testing:APM44BridgeTests` fails with
`Could not find test host` — `TEST_HOST` resolves to `APM44Bridge.app` but the
product bundle is `APM44 Bridge.app` (space). This is a project-config / xcodegen
mismatch independent of the source edits here. Flagged for separate follow-up.

## Status
**Complete.** User reviewed the live build and approved ("way better"). Code
committed to `master` as `cd29a15`.

### Observed at runtime (not regressions)
- Start button / selected segment render gray when the app isn't the active app
  (artifact of launching the dev build detached; accent-blue under normal use).
- Output dropdown shows blank when the saved device UID isn't in the current
  device list (e.g. AirPods not connected). Placeholder only shows when no UID is
  saved — a "saved device unavailable" state is a possible future polish.
