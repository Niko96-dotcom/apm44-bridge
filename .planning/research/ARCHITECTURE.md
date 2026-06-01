# Architecture Research

**Domain:** APM44 Bridge — v1.1 production HAL path integration (menu bar ↔ daemon ↔ driver ↔ signing)
**Researched:** 2026-06-01
**Confidence:** HIGH (grounded in shipped v1.0 codebase and `.planning/PROJECT.md` milestone scope)

## Standard Architecture

### System Overview (v1.0 baseline + v1.1 delta)

v1.0 already implements **two parallel input paths** into the same RT engine (`BridgeEngine`). v1.1 does not change the audio graph; it **closes the control-plane gap** (menu bar → correct CLI mode), **hardens the HAL contract** (44100-only nominal rates), and **unblocks host QA** (Developer ID signed driver load).

```
┌──────────────────────────────────────────────────────────────────────────┐
│  DAW @ 44.1 kHz (Cubase 15 sign-off target)                               │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │ Core Audio playback
         ┌───────────────────┴───────────────────┐
         │ PRODUCTION (v1.1 target)             │ MVP FALLBACK (unchanged)
         ▼                                       ▼
┌─────────────────────────┐            ┌─────────────────────────┐
│ APM44Bridge.driver      │            │ BlackHole 2ch @ 44100   │
│ (coreaudiod, libASPL)   │            │ (user-installed, GPL)   │
│ UID com.niko.apm44...   │            │ HAL input IOProc        │
└───────────┬─────────────┘            └───────────┬─────────────┘
            │ mmap SPSC shm (producer)              │ HAL input IOProc
            │ OnWriteMixedOutput → ring             │ onInput → ring
            ▼                                       │
┌───────────────────────────────────────────────────┴──────────────────────┐
│  apm44-bridge (BridgeDaemon) — C++ RT core                                  │
│  --virtual-device  → VirtualDeviceFeed (shm consumer) ─┐                    │
│  default path      → input IOProc @ 44100 ────────────┤→ PlanarRingBuffer  │
│                        LibSamplerateSrc + DriftController                   │
│                        output IOProc @ 48000 → AirPods Max USB-C            │
└────────────────────────────────────────────────────────────────────────────┘
            ▲
            │ subprocess spawn (stdout JSON metrics)
┌───────────┴──────────────────────────────────────────────────────────────────┐
│  APM44 Bridge.app (SwiftUI MenuBarExtra) — NON-RT                             │
│  v1.1: detect HAL presence → pass --virtual-device; else BlackHole path     │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│  Release / QA plane (v1.1 hard gate)                                          │
│  codesign(driver,app,daemon) → install HAL → kickstart coreaudiod → AMS/DAW  │
│  → Cubase matrix + 30 min soak + validate-export-rate.sh                      │
└──────────────────────────────────────────────────────────────────────────────┘
```

**v1.1 delta (bold in diagram):** menu bar routing mode; DRV-02 nominal-rate list; signed install path for AMS/Cubase enumeration (DEV-01, DEV-03).

### Component Responsibilities

| Component | Responsibility | v1.1 status |
|-----------|----------------|-------------|
| `APM44Bridge.driver` | Virtual output @ 44100; copy DAW PCM → shm; never touch AirPods | **Modify** — DRV-02 44100-only nominal list; optional format hardening deferred |
| `Shared/` (`MmapShmRing`, `ShmRingLayout`) | Cross-process SPSC ring layout + mmap | **Unchanged** — contract stable |
| `apm44-bridge` | SRC, drift, output @ 48; `--virtual-device` shm consumer | **Unchanged** — flag already implemented |
| `BridgeProcessManager` (App) | Spawn/stop daemon, metrics, device picker | **Modify** — add `--virtual-device` when HAL loaded |
| `DeviceCatalog` / `BridgeBinaryLocator` | List devices via CLI; resolve binary | **Modify** — HAL presence probe (new helper) |
| Signing scripts + `docs/release.md` | Developer ID, notarytool, install | **Execute** — was docs-only in v1.0; v1.1 hard gate |
| QA scripts (`verify-hal-driver.sh`, `validate-export-rate.sh`, DAW matrix) | Human/automated sign-off | **Run** after signed HAL load |

### Recommended Project Structure (unchanged)

```
Driver/APM44Bridge.driver/     # HAL plug-in (libASPL)
BridgeDaemon/                  # apm44-bridge + engine + hal/
App/APM44Bridge/               # Swift menu bar
Shared/                        # ring, drift, formats
scripts/                       # install-driver, verify-hal-driver, validate-export-rate
docs/                          # hal-driver, release, daw-matrix (Cubase row to add)
```

**Rationale:** v1.1 is an **integration milestone** on the existing vertical slice—no new top-level module unless HAL detection logic grows enough to warrant `App/APM44Bridge/RoutingMode.swift` (recommended).

## Architectural Patterns

### Pattern 1: Dual input path, single engine

**What:** `BridgeEngine` accepts audio from either (a) HAL input IOProc on BlackHole or (b) shm drain in output IOProc when `virtualDevice == true`.

**When to use:** Always—production vs MVP is a **CLI flag**, not a forked binary.

**Trade-offs:** Keeps one SRC/drift/metrics pipeline; app must pick the flag correctly.

**Existing code path:**

```105:112:BridgeDaemon/src/engine/BridgeEngine.cpp
  if (virtualDevice_) {
    const std::size_t inputFramesNeeded = InputFramesForOutputFrames(frames);
    virtualFeed_.drainTo(ring_, inputFramesNeeded + 256);
  }
```

### Pattern 2: Subprocess bridge control (defer XPC)

**What:** Menu bar spawns `apm44-bridge` with arguments; parses `--metrics-json` lines on stdout.

**v1.1 change:** Extend `buildArguments()` only—no IPC redesign.

**Trade-offs:** Simple and shipped; detection of HAL vs BlackHole belongs in Swift before spawn.

### Pattern 3: HAL presence → routing mode (v1.1 new)

**What:** At start (and optionally on hotplug refresh), decide:

| Condition | Daemon args | DAW routes to |
|-----------|-------------|---------------|
| `APM44 Bridge` visible @ 44100 (UID `com.niko.apm44.bridge.device`) | `--virtual-device` + `--output-device <AirPods UID>` | APM44 Bridge |
| Else | default (BlackHole input) + `--output-device` | BlackHole 2ch |

**Detection options (pick one, prefer A):**

- **A (recommended):** Reuse `DeviceCatalog.refresh()` — row where `uid == "com.niko.apm44.bridge.device"` and `nominalRate ≈ 44100`.
- **B:** Shell out to `scripts/verify-hal-driver.sh` (structural + `system_profiler`); heavier, better for CI than per-click UI.
- **C:** User override in settings (“Force BlackHole” / “Force HAL”) for support/debug.

**Trade-offs:** Auto-detect can race driver install/reload; show banner when mode switches.

### Pattern 4: Sign-before-host-QA gate

**What:** Treat **signed HAL load** as infrastructure prerequisite for DEV-01/DEV-03/Cubase matrix—not a post-QA polish step.

**When:** macOS 15+ may refuse ad-hoc HAL bundles before plug-in code runs (`docs/release.md`, v1.0 audit).

## Data Flow

### Production audio flow (HAL path)

```
DAW render callback
  → coreaudiod → APM44Bridge.driver OnWriteMixedOutput (SInt16 → float in shm)
  → MmapShmRing (producer, Driver process)
  → VirtualDeviceFeed::drainTo (consumer, apm44-bridge process)
  → PlanarRingBuffer → libsamplerate (variable ratio) → output IOProc
  → AirPods @ 48000 Hz
```

**Timing note:** In virtual-device mode, input is **pulled on the output IOProc** (no separate input HAL client). DAW must be playing into the virtual device while daemon runs.

### Control flow (v1.1 target)

```
User clicks Start (MenuBar)
  → BridgeProcessManager.start()
  → HalRoutingPolicy.resolve()  [NEW]
       ├─ HAL present → args include --virtual-device
       └─ else → args omit flag (BlackHole input path)
  → Process.spawn(apm44-bridge, args)
  → metrics JSON → UI meters / glitch flash
```

### BlackHole fallback flow (unchanged)

```
DAW → BlackHole @ 44100
  → apm44-bridge input IOProc → ring → SRC → AirPods @ 48000
```

Menu bar **must not** remove this path—v1.1 requirement is additive.

## v1.1 Integration Map

### New components (App layer)

| Artifact | Purpose |
|----------|---------|
| `HalRoutingPolicy` (or `BridgeRoutingMode.swift`) | Encapsulate HAL detection + `buildArguments()` branch |
| Optional `BridgeSettings.routingPreference` | `automatic` \| `hal` \| `blackhole` |
| UI copy in `MenuContentView` | Show active path (“APM44 Bridge (driver)” vs “BlackHole”) |

### Modified components

| Artifact | Change |
|----------|--------|
| `BridgeProcessManager.buildArguments()` | Append `--virtual-device` when policy says HAL |
| `BridgeProcessManager` / banners | Warn if user starts HAL mode but device not in AMS list |
| `Driver/src/Driver.cpp` (+ libASPL hook) | DRV-02: `GetAvailableSampleRates()` → single 44100 entry |
| `docs/daw-matrix.md` | Cubase 15 primary row (operator constraint) |
| `docs/hal-driver.md` | Remove “menu bar defaults to BlackHole” after wire-up |
| `CliOptions` usage text | Optional: mention app auto-selects virtual device |

### Unchanged (do not rework in v1.1)

| Artifact | Reason |
|----------|--------|
| `BridgeEngine`, `LibSamplerateSrc`, `DriftController` | Already production-ready |
| `VirtualDeviceFeed`, `ShmIoHandler` | Shm path complete |
| `MmapShmRing` layout | Cross-version contract |
| XPC daemon control | Explicitly deferred |

### External boundaries

| Boundary | Communication | v1.1 notes |
|----------|---------------|------------|
| DAW ↔ HAL device | Core Audio device list | Requires **signed** driver for reliable enumeration on target Mac |
| Driver ↔ Daemon | POSIX shm (`MmapShmRing`) | Daemon must start **after** DAW selects device and driver IO is active |
| App ↔ Daemon | `Process` + stdout JSON | Add one CLI flag; no protocol change |
| App ↔ HAL | **None** (by design) | Detection via Core Audio enumeration only |
| Release ↔ Runtime | `codesign` + `install-driver` / manual cp | Signing does not change runtime graph |

## Suggested Build Order

Dependencies drive ordering: **driver contract fixes** and **signing** unblock **host QA**; **app wiring** can proceed in parallel on unsigned dev machines but **milestone done** requires all three.

```
Phase A (parallel)          Phase B                 Phase C
─────────────────          ─────────               ─────────
DRV-02 driver hardening    App HAL routing wire    Human QA stack
Signing pipeline dry-run   (BridgeProcessManager)   Cubase 15 matrix
                           Docs / matrix update     30 min HAL soak
                                                    QA-02 export script
```

### Recommended sequence (opinionated)

| Order | Workstream | Rationale | Blocks |
|-------|------------|-----------|--------|
| **1** | **Signing pipeline** (Release build → `codesign` driver/daemon/app → install → `kickstart` coreaudiod) | macOS 15+ HAL QA is invalid on ad-hoc-only; DEV-01/DEV-03 are false negatives without it | AMS enumeration, Cubase device list, soak |
| **2** | **DRV-02 driver hardening** (44100-only `GetAvailableSampleRates`) | Small Driver/ change; verify with `verify-hal-driver.sh` + AMS | DAW rate mismatch bugs |
| **3** | **App wiring** (`--virtual-device` when HAL present) | Depends on stable driver **identity** in device list, not strictly on signing for dev | End-user “one click” production path |
| **4** | **Human QA** (Cubase @ 44100 → APM44 Bridge, export bounce, 30 min soak) | Requires 1–3 on sign-off machine | Milestone complete |

**Parallelization:** Steps 1 and 2 can run in parallel if two people/machines; step 3 can start on unsigned HAL for logic/unit tests, but **do not mark APP integration done** until tested against **signed** bundle from step 1.

**Anti-ordering:** Do not block signing on app wiring—signing is the long pole for HAL QA. Do not block app wiring on DRV-02 unless AMS shows wrong rate list during dev.

### CI vs human gates

| Layer | Automated (keep) | Human (v1.1) |
|-------|------------------|--------------|
| Build | cmake Release, ctest | — |
| Driver struct | `verify-hal-driver.sh` (bundle only) | `system_profiler` after **signed** install |
| App | Swift tests + build | Menu bar spawns correct flag |
| Audio | offline soak harness | 30 min live HAL + Cubase |

## Anti-Patterns

### Anti-Pattern 1: Signing after DAW QA

**What people do:** Run Cubase matrix on ad-hoc driver, then sign at the end.

**Why it's wrong:** Failures from AMFI/Gatekeeper masquerade as driver bugs; wasted matrix cycles.

**Do this instead:** First signed install on the sign-off Mac; then DEV-01/DEV-03/Cubase.

### Anti-Pattern 2: App opens HAL or shm directly

**What people do:** Swift code mmap’s shm or loads the plug-in.

**Why it's wrong:** Violates process boundaries; RT unsafe; duplicates daemon.

**Do this instead:** App only spawns `apm44-bridge` with `--virtual-device`.

### Anti-Pattern 3: Removing BlackHole path when HAL ships

**What people do:** Single code path for “production only.”

**Why it's wrong:** v1.1 explicitly keeps fallback; GPL BlackHole is user-installed, not bundled.

**Do this instead:** Auto-detect with manual override; document both in UI.

### Anti-Pattern 4: Forcing 44100 on AirPods in daemon or driver

**What people do:** Set nominal rate on output device to match DAW.

**Why it's wrong:** Hardware is 48 kHz; breaks monitoring model (PROJECT out of scope).

**Do this instead:** Virtual device lies at 44100; SRC only in daemon output path.

## Scaling Considerations

Not user-scale—**session-scale** (one producer, one machine):

| Concern | v1.1 | Later |
|---------|------|-------|
| Single DAW instance | Cubase 15 matrix | Logic/Ableton rows |
| One virtual device UID | Fixed `com.niko.apm44.bridge.device` | Pro Tools engine (v2) |
| Subprocess per bridge | Acceptable | XPC + launchd agent |

## Integration Points (checklist for roadmap)

- [ ] **HAL detection** in app via `com.niko.apm44.bridge.device` in `--list-devices` output
- [ ] **`--virtual-device`** appended in `BridgeProcessManager.buildArguments()` when HAL mode
- [ ] **DRV-02** — libASPL `GetAvailableSampleRates()` override → 44100 only
- [ ] **Signed** `APM44Bridge.driver` installed under `/Library/Audio/Plug-Ins/HAL/`
- [ ] **coreaudiod** reload after install
- [ ] **Cubase 15** output = APM44 Bridge @ 44100; daemon → AirPods @ 48
- [ ] **QA-02** `scripts/validate-export-rate.sh` on bounce
- [ ] **30 min** soak on HAL path (not BlackHole-only)
- [ ] **notarytool** dry-run documented in `docs/release.md` (container submit)

## Sources

- `.planning/PROJECT.md` — v1.1 milestone scope and architecture diagram
- `.planning/milestones/v1.0-MILESTONE-AUDIT.md` — Phase 4 gap (menu bar / unsigned HAL)
- `App/APM44Bridge/BridgeProcessManager.swift` — current spawn args (no `--virtual-device`)
- `BridgeDaemon/src/main.cpp`, `CliOptions.cpp`, `BridgeEngine.cpp` — dual path implementation
- `Driver/src/Driver.cpp`, `ShmIoHandler.cpp` — HAL producer @ 44100
- `docs/hal-driver.md`, `docs/release.md` — install and signing workflow
- Apple Audio Server Plug-in guidance (virtual devices via ASPL, not DriverKit) — HIGH confidence per `CLAUDE.md` / PROJECT constraints

---
*Architecture research for: APM44 Bridge v1.1 Production Sign-Off*
*Researched: 2026-06-01*
