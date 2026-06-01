# Stack Research

**Domain:** macOS audio bridge — v1.1 production sign-off (signing, Cubase 15 QA, HAL rate hardening, app ↔ daemon wiring)  
**Researched:** 2026-06-01  
**Confidence:** HIGH for Apple signing/notarization and Core Audio HAL patterns; MEDIUM for Cubase 15 host-specific quirks (forum reports of sample-rate fights on some interfaces; APM44 is a fixed 44.1 virtual device)

**Baseline (unchanged — do not re-research):** macOS 14+, Xcode 16, C++20 `apm44-bridge`, SwiftUI menu bar, libASPL **v3.1.2**, libsamplerate **0.2.2**, POSIX shm SPSC ring, CMake 3.28+ monorepo. See `CLAUDE.md` and prior v1.0 stack rows.

---

## Recommended Stack

### Core Technologies (v1.1 additions)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Apple Developer Program** | Current membership | Issue **Developer ID Application** cert | HAL plug-ins on macOS 15+ commonly fail AMFI/load checks when ad-hoc signed; v1.1 hard gate is signed driver on real hardware ([tympan-aspl notes](https://github.com/penta2himajin/tympan-aspl), project audit) |
| **Developer ID Application** certificate | Latest from Apple PKI | Sign `.app`, `apm44-bridge`, `APM44Bridge.driver` | Apple requires Developer ID (not Mac Development / ad hoc) for notarized distribution ([Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)) |
| **`codesign`** | Xcode **16.x** CLT (bundled) | Hardened runtime signatures on all shipped Mach-O + bundles | HAL runs inside `coreaudiod`; bundle-level `--deep --strict` verify catches post-sign edits |
| **`xcrun notarytool`** | Xcode **16.x** | Upload zip/dmg/pkg for malware scan | Replaces deprecated `altool` (unsupported after 2023); supports `--wait`, keychain profiles, optional webhook ([Customizing notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)) |
| **`xcrun stapler`** | Xcode **16.x** | Attach notarization ticket to `.app` (offline Gatekeeper) | Staple the **outermost distributable** users run; re-zip after staple if shipping download zip |
| **Hardened Runtime** | `--options runtime` on every shipped binary | Notarization prerequisite | Apple lists hardened runtime + secure timestamp + Developer ID as mandatory for notarization |
| **libASPL** | **v3.1.2** (pinned, existing) | DRV-02: `SetAvailableSampleRatesAsync()` | Only API change needed for **44100-only** nominal list; avoids hosts offering 48 kHz on virtual device ([`Device.hpp` GetAvailableSampleRates / SetAvailableSampleRatesAsync](https://github.com/gavv/libASPL)) |
| **Cubase Pro** | **15.x** (operator matrix) | Primary DAW sign-off host | macOS uses **Core Audio**, not ASIO ([Steinberg built-in ASIO — macOS](https://helpcenter.steinberg.de/hc/en-us/articles/17863730844946)); no Steinberg SDK or VST wrapper required for device routing |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| *(none new)* | — | v1.1 is tooling + HAL property + Swift spawn wiring | No new audio/SRC dependencies |

### Development Tools (v1.1)

| Tool | Purpose | Notes |
|------|---------|-------|
| **`security find-identity -v -p codesigning`** | Resolve exact `SIGN_ID` string | Use full `"Developer ID Application: … (TEAMID)"` or cert hash if ambiguous |
| **`xcrun notarytool store-credentials`** | CI/local notary auth | Profile e.g. `AC_NOTARY`; prefer API key in CI over Apple ID password |
| **`codesign --verify --deep --strict`** | Pre-flight before notary | Run on `.driver`, `.app`, and standalone `apm44-bridge` |
| **`spctl -vvv --assess --type exec`** | Gatekeeper dry-run on stapled `.app` | Confirms user-facing open path after staple |
| **`ditto -c -k --keepParent`** | Notarization container | Apple expects zip/dmg/pkg, not loose `.driver` ([`docs/release.md`](../../docs/release.md)) |
| **`scripts/verify-hal-driver.sh`** | Structural HAL bundle checks | Extend v1.1: optional `codesign -dv` when `SIGN_ID` set; already greps `system_profiler` for **APM44 Bridge** |
| **`scripts/install-driver.sh`** | Root install + `coreaudiod` kickstart | Dev: ad-hoc; release: install **pre-signed** bundle only |
| **`scripts/verify-devices.sh`** | Pre-flight rates | Extend: detect **APM44 Bridge @ 44100** (production path), keep BlackHole checks for fallback |
| **`scripts/validate-export-rate.sh`** | QA-02 (`afinfo`) | Extend `--instructions` with **Cubase 15** export steps (no new binary dep) |
| **`afinfo`** | macOS built-in | Assert bounced WAV/AIFF remains **44100 Hz** |
| **`system_profiler SPAudioDataType`** | macOS built-in | AMS-visible device + format lines for DEV-01 matrix evidence |
| **CMake `CODESIGN_ID` cache** (recommended) | Post-build driver sign | Mirror [libASPL SinewaveDevice example](https://github.com/gavv/libASPL): `cmake -DCODESIGN_ID="Developer ID Application: …"` → post-build `codesign` on `APM44Bridge.driver` |

### Code signing & notarization (detailed)

| Step | Tool / artifact | Why |
|------|-----------------|-----|
| 1. Build Release | `cmake -DCMAKE_BUILD_TYPE=Release && cmake --build build --target APM44Bridge apm44-bridge` (+ app target) | Same monorepo; signing applies to **built** paths under `build/` |
| 2. Sign daemon | `codesign --force --sign "$SIGN_ID" --timestamp --options runtime build/BridgeDaemon/apm44-bridge` | CLI is a standalone Mach-O; sign before embedding in `.app` if copied into bundle |
| 3. Sign HAL | `codesign --force --sign "$SIGN_ID" --timestamp --options runtime --entitlements Driver/APM44Bridge.entitlements build/Driver/APM44Bridge.driver` | Entitlements plist is **empty dict** — correct for HAL (no app sandbox) |
| 4. Sign app | `codesign … --entitlements App/APM44Bridge/APM44Bridge.entitlements` on `APM44 Bridge.app` | Sign inner `apm44-bridge` first if bundled via `Contents/MacOS` or `Contents/Resources` |
| 5. Package | Zip app (+ optional separate `APM44Bridge-driver.zip`) or **pkg** with `postinstall` → `/Library/Audio/Plug-Ins/HAL/` | Notarize **container only**; staple `.app`, not the zip |
| 6. Submit | `xcrun notarytool submit … --keychain-profile AC_NOTARY --wait` | Dry-run = real submit on hardware Mac with credentials (v1.1 gate) |
| 7. Staple + validate | `xcrun stapler staple` + `stapler validate` | Required for offline Gatekeeper on end-user Macs |

**Entitlements (no new keys for v1.1):**

| Bundle | File | Policy |
|--------|------|--------|
| `APM44 Bridge.app` | `App/APM44Bridge/APM44Bridge.entitlements` | Minimal / empty; add keys only if notarization log demands (e.g. hardened-runtime exceptions) |
| `APM44Bridge.driver` | `Driver/APM44Bridge.entitlements` | Empty; **never** enable App Sandbox on HAL plug-in |

**Optional v1.1 script:** `scripts/sign-release.sh` wrapping the above + env vars `SIGN_ID`, `TEAM_ID`, `NOTARY_PROFILE` — keeps CMake focused on compile, matches existing `docs/release.md`.

### Cubase 15 + Core Audio routing (QA stack)

Cubase does **not** ship a separate macOS HAL API — it selects the same Core Audio devices as Logic/Ableton via **Studio → Studio Setup** (ASIO Driver page) and **Edit → Audio Settings** ([Cubase Pro 15 — Audio Settings](https://www.steinberg.help/r/cubase-pro/15.0/en/cubase_nuendo/topics/setting_up/setting_up_audio_settings_r.html)).

| Layer | What to configure | Expected for APM44 |
|-------|-------------------|----------------------|
| **Audio MIDI Setup** | **APM44 Bridge** format **44.1 kHz**; AirPods USB-C **48 kHz** | DEV-01; matches virtual device truth |
| **Cubase project** | Project setup sample rate **44100 Hz** | Session metadata stays 44.1 |
| **Cubase output** | Studio Setup → driver = Core Audio device list → **APM44 Bridge** stereo out | DEV-03; **HW Sample Rate** should read **44100** when device is selected |
| **Monitoring** | Menu bar or CLI: `apm44-bridge --virtual-device --output-device <AirPods UID>` | Production path; DAW does not talk to AirPods directly |
| **QA-02 export** | **File → Export → Audio Mixdown** (or equivalent) at project rate | `bash scripts/validate-export-rate.sh --check-file …` via **`afinfo`** |

**No new Cubase SDK, VST, or ASIO driver** — validation is human matrix + existing shell tools. Update `docs/daw-matrix.md` with a **Cubase 15** section (parallel to Logic/Ableton columns).

### Menu bar `--virtual-device` wiring (app stack)

| Piece | Implementation | Why |
|-------|----------------|-----|
| **Detection** | Check `/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver` exists **or** `system_profiler SPAudioDataType` contains `APM44 Bridge` | Filesystem check works pre-DAW; profiler confirms loaded HAL |
| **Spawn** | `BridgeProcessManager.buildArguments()` adds `"--virtual-device"` when HAL path active; else keep BlackHole default (no `--input-device`) | Closes v1.0 audit gap; single daemon binary, no XPC |
| **Preflight** | Reuse `apm44-bridge --preflight` / `--list-devices` from `DeviceCatalog` | Already locates binary via `BridgeBinaryLocator` |
| **UX** | Menu copy: “Routing: APM44 Bridge (driver)” vs “BlackHole (fallback)” | Honest when driver unsigned/missing |

No new Swift packages; `Process` + existing settings model only.

### DRV-02 — 44100 Hz only (driver stack)

| API | Usage |
|-----|--------|
| `deviceParams.SampleRate = 44100` | Already set in `Driver/src/Driver.cpp` |
| `device->SetAvailableSampleRatesAsync({{44100.0, 44100.0}})` | **v1.1 add** after device creation — discrete range min=max per libASPL docs |
| Stream `streamParams.Format.mSampleRate` | Keep **44100** aligned with nominal list |

**Verification (no new tools):** AMS shows only 44.1 kHz for **APM44 Bridge**; optional host test Cubase **HW Sample Rate** locked at 44100; `bash scripts/verify-hal-driver.sh` remains structural — add manual matrix row for rate list.

---

## Installation

```bash
# --- Signing prerequisites (one-time, release machine or CI) ---
# Apple Developer Program + create "Developer ID Application" in Xcode → Accounts → Manage Certificates
security find-identity -v -p codesigning

xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "<notarytool-password>"

# --- Release build + sign (see docs/release.md) ---
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target APM44Bridge apm44-bridge   # + app target when configured

export SIGN_ID="Developer ID Application: Your Name (TEAMID)"
codesign --force --sign "$SIGN_ID" --timestamp --options runtime \
  --entitlements Driver/APM44Bridge.entitlements \
  build/Driver/APM44Bridge.driver

# Optional: CMake-integrated sign
# cmake -DCODESIGN_ID="$SIGN_ID" ... && cmake --build build --target APM44Bridge

# --- Notarization dry-run (v1.1 gate) ---
ditto -c -k --keepParent "build/Release/APM44 Bridge.app" APM44Bridge-app.zip
xcrun notarytool submit APM44Bridge-app.zip --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple "build/Release/APM44 Bridge.app"

# --- HAL install (signed bundle only for production) ---
sudo cp -R build/Driver/APM44Bridge.driver /Library/Audio/Plug-Ins/HAL/
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
sudo launchctl kickstart -k system/com.apple.audio.coreaudiod

# --- Cubase / QA helpers (no install) ---
bash scripts/verify-devices.sh          # extend for APM44 @ 44100
bash scripts/verify-hal-driver.sh
bash scripts/validate-export-rate.sh --instructions   # add Cubase 15 section
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| **Developer ID Application** + `notarytool` | Ad-hoc `codesign -s -` via `install-driver.sh` | Local dev only; fails v1.1 production gate on many macOS 15+ systems |
| **Zip + notarytool + staple `.app`** | **Developer ID Installer** + `.pkg` | When shipping one installer that copies HAL to `/Library/Audio/Plug-Ins/HAL/` with `postinstall` — needs second cert |
| **`notarytool` + keychain profile** | Apple ID password on CLI | One-off laptop dry-run only; CI should use API key / stored profile |
| **libASPL `SetAvailableSampleRatesAsync`** | Custom override of `GetAvailableSampleRates()` | Only if async set races host enumeration; prefer async set once at init |
| **Filesystem HAL detection in app** | Parse `apm44-bridge --list-devices` only | Use both: file check is cheap; profiler confirms load |
| **Cubase 15 manual matrix** | Steinberg test harness / ARA | No public “device QA” API; Core Audio path is what users actually hit |
| **CMake post-build `codesign`** | Xcode-only signing UI | CMake already owns `.driver` bundle; post-build sign keeps single pipeline |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **`altool --notarize-app`** | Deprecated / unsupported | `xcrun notarytool submit` |
| **Notarize loose `.driver` or raw `apm44-bridge`** | Apple rejects non-container uploads | Zip/dmg/pkg, then staple user-facing bundle |
| **App Sandbox on `APM44Bridge.driver`** | Breaks / wrong model for HAL in `coreaudiod` | Empty driver entitlements |
| **DriverKit / kernel extension signing** | Wrong product class for virtual HAL plug-in | Audio Server Plug-in + Developer ID Application |
| **Steinberg ASIO driver on macOS** | Not applicable | Core Audio device list in Cubase |
| **Forcing Cubase to set AirPods rate** | Out of scope; breaks monitoring model | DAW → APM44 @ 44.1 only; bridge owns 48 kHz output |
| **New DAW-specific IPC SDK** | No gain for output-device workflow | HAL + existing CLI flags |

---

## Stack Patterns by Variant

**If Apple Developer credentials are available (v1.1 default):**

- Sign all three artifacts → notarize stapled `.app` zip → install signed `.driver` on QA Mac → run Cubase matrix + 30 min soak on **HAL path**.

**If signing blocked (interim dev only):**

- Ad-hoc `install-driver.sh` + CLI `--virtual-device` — **does not satisfy** v1.1 milestone; document as dev-only in README.

**If HAL installed and visible:**

- Menu bar spawns `apm44-bridge` with `--virtual-device`; skip BlackHole input device args.

**If HAL missing:**

- Menu bar keeps MVP path (BlackHole @ 44.1 → bridge); banner explains install/sign steps.

**If shipping driver to end users without manual `cp`:**

- Add **Developer ID Installer** cert + signed `.pkg` `postinstall` (optional v1.1.1; not required if docs + manual install acceptable for first signed release).

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Xcode **16.x** | macOS **14–15** SDK | `MACOSX_DEPLOYMENT_TARGET=14.0` unchanged |
| `notarytool` (Xcode 15.4+) | Apple notary service | Same toolchain as `codesign` |
| Signed HAL + macOS **15.x** | Developer ID Application | Ad-hoc HAL often blocked before plug-in runs |
| libASPL **v3.1.2** | DRV-02 rate APIs | Pin unchanged; rate hardening is call-site only |
| Cubase **15.x** | macOS 14+ Core Audio | Matrix version pinned in `docs/daw-matrix.md` sign-off table |
| CMake **3.28+** | `CODESIGN_ID` post-build | Optional; does not replace notarization container step |

---

## CI integration (v1.1 recommendation)

| Job | Runs on | Secrets | Scope |
|-----|---------|---------|-------|
| **build-test** (existing) | `macos-latest` | none | `cmake --build`, `ctest`, `scripts/ci-soak.sh` — **no HAL install** |
| **sign-notarize** (new, optional) | `macos-latest` | `DEVELOPER_ID_APPLICATION`, `DEV_ID_APP_CERT`, `DEV_ID_APP_PASSWORD`, `TEAM_ID`, notary profile | Build Release → sign → `notarytool submit` → upload artifacts |
| **hal-verify** (manual / nightly) | physical Mac | signing secrets | `install-driver.sh` + `verify-hal-driver.sh` + Cubase matrix |

**Do not** fail PR CI on missing Apple secrets — keep sign/notarize as **workflow_dispatch** or release tag until credentials exist (matches `docs/release.md` “Manual” row, elevated to scripted dry-run for v1.1).

---

## Sources

| Source | Confidence | Used for |
|--------|------------|----------|
| [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) | HIGH | Developer ID, hardened runtime, timestamp |
| [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) | HIGH | `notarytool submit`, `store-credentials` |
| [Melatonin — code sign & notarize audio plugins in CI](https://melatonin.dev/blog/how-to-code-sign-and-notarize-macos-audio-plugins-in-ci/) | MEDIUM | HAL/plugin CI patterns, container rule |
| [Steinberg — no ASIO on macOS](https://helpcenter.steinberg.de/hc/en-us/articles/17863730844946) | HIGH | Cubase uses Core Audio |
| [Cubase Pro 15 — Audio Settings](https://www.steinberg.help/r/cubase-pro/15.0/en/cubase_nuendo/topics/setting_up/setting_up_audio_settings_r.html) | HIGH | Studio Setup / HW sample rate UI |
| [libASPL Device.hpp — available sample rates](https://github.com/gavv/libASPL/blob/main/include/aspl/Device.hpp) | HIGH | DRV-02 `SetAvailableSampleRatesAsync` |
| Repo `docs/release.md`, `Driver/src/Driver.cpp`, `App/APM44Bridge/BridgeProcessManager.swift` | HIGH | Current implementation gaps |
| [tympan-aspl macOS 15 signing notes](https://github.com/penta2himajin/tympan-aspl) | MEDIUM | Ad-hoc vs Developer ID on HAL |

---
*Stack research for: APM44 Bridge v1.1 Production Sign-Off*  
*Researched: 2026-06-01*
