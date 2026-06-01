# Pitfalls Research

**Domain:** APM44 Bridge — v1.1 Production Sign-Off (HAL signing, Cubase routing, app/daemon integration, DRV-02)
**Researched:** 2026-06-01
**Confidence:** HIGH (project audit + codebase + Apple/Melatonin/tympan-aspl); MEDIUM (Cubase 15 host-specific edge cases)

## Critical Pitfalls

### Pitfall 1: Treating ad-hoc HAL signing as “good enough” on macOS 15+

**What goes wrong:**
`APM44 Bridge` never appears in Audio MIDI Setup or Cubase. `coreaudiod` may log AMFI failures (e.g. `AppleMobileFileIntegrityError -423`) and abort plug-in load before any device code runs. v1.1’s hard gate (“signed HAL loads on a real Mac”) fails while local dev on SIP-disabled machines still “works.”

**Why it happens:**
v1.0 shipped `scripts/install-driver.sh` with ad-hoc `codesign --sign -` for iteration. Audit and `docs/release.md` document macOS 15+ rejection, but teams often re-run the dev script and interpret “install succeeded” as “driver loaded.”

**How to avoid:**
- Sign `APM44Bridge.driver` with **Developer ID Application** (not Installer), `--options runtime`, `--timestamp`, and `Driver/APM44Bridge.entitlements`.
- Verify before install: `codesign --verify --deep --strict --verbose=2 build/Release/APM44Bridge.driver`.
- Install to `/Library/Audio/Plug-Ins/HAL/`, `chown root:wheel`, then `sudo launchctl kickstart -k system/com.apple.audio.coreaudiod`.
- Record proof: `system_profiler SPAudioDataType` or AMS screenshot + `log show` grep for AMFI/coreaudiod plug-in errors.

**Warning signs:**
- Device missing immediately after kickstart; no `APM44 Bridge` in `apm44-bridge --list-devices`.
- Console shows AMFI / code signature errors for `APM44Bridge.driver`.
- Works on one Mac (unsigned dev) but not on a clean macOS 15+ machine.

**Phase to address:**
**v1.1 — HAL signing & load verification** (SHIP / hard gate)

---

### Pitfall 2: Wrong codesign identity, entitlements, or signing order

**What goes wrong:**
Sign step succeeds but load fails; notarization rejects with hardened-runtime violations; or nested Mach-O in the bundle stays ad-hoc while the bundle wrapper is signed.

**Why it happens:**
HAL bundles are CFPlugIn packages with a `Contents/MacOS` binary. Audio plug-in tutorials often target `.component`/`.vst3` and use **Developer ID Application** — easy to grab **Developer ID Installer** by mistake for a `.driver`. Empty driver entitlements are correct; copying app sandbox entitlements onto the driver breaks expectations.

**How to avoid:**
- Use exactly: `Developer ID Application: … (TEAMID)` per `docs/release.md`.
- Sign the inner executable, then the `.driver` bundle (deep verify).
- Keep `Driver/APM44Bridge.entitlements` minimal — no app sandbox on HAL.
- Sign `apm44-bridge` and `APM44 Bridge.app` with the same identity before notarizing containers that include them.

**Warning signs:**
`codesign -dv` shows `Signature=adhoc` on `Contents/MacOS/*` inside the driver.
`notarytool log` cites disallowed entitlements or unsigned nested code.

**Phase to address:**
**v1.1 — HAL signing & load verification**

---

### Pitfall 3: Confusing “notarized app” with “loadable HAL plug-in”

**What goes wrong:**
Team notarizes/staples only `APM44 Bridge.app`, installs an **unsigned** or stale `.driver`, and spends days debugging Cubase routing. Gatekeeper may be happy with the app while `coreaudiod` still refuses the plug-in.

**Why it happens:**
Notarization is a **distribution** check; HAL load on macOS 15+ is an **AMFI + Developer ID** check at plug-in load time (tympan-aspl, project audit). These are related but not interchangeable.

**How to avoid:**
- Treat **signed driver load** as its own acceptance test (DEV-01), separate from app notarization dry-run.
- Notarize a **zip** of the signed `.driver` (and/or a pkg that installs to HAL) via `notarytool submit`; download log on failure.
- Staple applies to the **distributed container** you ship; re-copy stapled driver to HAL after staple if distributing loose `.driver`.
- Do not submit raw `.driver` to notarytool without a supported container (zip/dmg/pkg) — Apple’s tool rejects unsupported formats.

**Warning signs:**
`notarytool` accepted an app zip but HAL never enumerates.
QA matrix marks “production path” pass based on menu bar only.

**Phase to address:**
**v1.1 — HAL signing & load verification** (notary dry-run); **v1.1 — Cubase / DAW sign-off** (E2E only after HAL loads)

---

### Pitfall 4: Notarization workflow mistakes (container, staple, credentials)

**What goes wrong:**
Submit fails (“unsupported file format”), staple applied to `.zip` instead of app, or CI hangs on `--wait` without pulling `notarytool log`. Shipping unstapled builds causes first-launch Gatekeeper delays.

**Why it happens:**
`notarytool` only accepts UDIF disk images, signed flat installers, and **zip** archives — not a loose binary or unstaged folder. Melatonin/audio-CI guides emphasize: sign everything first, zip outer container, submit once, staple the **distributable** artifact.

**How to avoid:**
- Follow `docs/release.md`: `ditto -c -k --keepParent` for app; separate zip for driver if needed.
- Store credentials once: `notarytool store-credentials "AC_NOTARY" …`.
- On failure: `notarytool log <submission-id> --keychain-profile AC_NOTARY`.
- Staple: `xcrun stapler staple` on `.app` / `.pkg` / `.dmg` — **not** on the zip you uploaded.
- Dry-run checklist: submit → Accepted → staple → validate → install signed driver → enumerate device.

**Warning signs:**
`notarytool submit build/Release/APM44Bridge.driver` without zip.
Stapler says “Record not found” because staple targeted the upload zip.

**Phase to address:**
**v1.1 — HAL signing & load verification**

---

### Pitfall 5: Menu bar starts BlackHole path while DAW routes to APM44 Bridge

**What goes wrong:**
Cubase plays to **APM44 Bridge** (HAL) but `BridgeProcessManager` spawns `apm44-bridge` **without** `--virtual-device`, opening a BlackHole input IOProc. User hears silence or wrong device; DEV-03 never closes.

**Why it happens:**
v1.0 audit: `App/APM44Bridge/BridgeProcessManager.swift` `buildArguments()` only passes `--output-device`, `--target-fill-ms`, `--src-quality`, `--metrics-json`. HAL path was CLI-only (`docs/hal-driver.md`).

**How to avoid:**
- When HAL is installed and `com.niko.apm44.bridge.device` is enumerable, append `--virtual-device` to spawn args.
- Optional: hide/disable BlackHole-specific copy in UI when in HAL mode; show “HAL + daemon” banner.
- Manual QA until wired: always start daemon with `--virtual-device` when using production matrix.
- Add regression test or `verify-menu-bar.sh` assertion that HAL mode includes the flag.

**Warning signs:**
Metrics JSON runs but level meters in Cubase move while AirPods are silent.
`apm44-bridge` stderr mentions BlackHole / input device not found while DAW uses APM44.

**Phase to address:**
**v1.1 — App `--virtual-device` integration**

---

### Pitfall 6: Mode-detection and lifecycle bugs around `--virtual-device`

**What goes wrong:**
- Daemon starts before driver/shm is ready → empty ring, dropouts.
- Hotplug `stop()` / `start()` restarts without `--virtual-device`.
- Signed app spawns **unsigned** dev `build/BridgeDaemon/apm44-bridge` → Gatekeeper blocks subprocess.
- User runs `--preflight` expecting HAL checks; preflight still targets BlackHole UIDs.

**Why it happens:**
Subprocess MVP deferred XPC and explicit transport state machine. `BridgeBinaryLocator` prefers dev build paths when env vars point at repo.

**How to avoid:**
- Centralize `BridgeLaunchProfile` (blackhole | virtualDevice) used by `buildArguments`, hotplug, and error strings.
- After `install-driver.sh` + kickstart, call `verify-hal-driver.sh` before auto-start.
- Embed signed `apm44-bridge` in app bundle for release builds; use `APM44_BRIDGE_PATH` only in dev.
- In virtual mode, skip BlackHole UID resolution; validate AirPods @ 48 kHz only (`FormatNegotiator::negotiateVirtualOutput`).

**Warning signs:**
First start after install fails; second manual CLI start works.
Hotplug recovery loses audio until user toggles bridge off/on.

**Phase to address:**
**v1.1 — App `--virtual-device` integration**

---

### Pitfall 7: DRV-02 “44100 only” implemented as default rate, not as exclusive capability

**What goes wrong:**
AMS or Cubase still offers 48 kHz (or rate switches succeed). DAW runs at 48 kHz while bridge assumes 44.1 → SRC ratio wrong, export QA-02 fails, or `SetNominalSampleRate` succeeds on unsupported rates.

**Why it happens:**
`Driver/src/Driver.cpp` sets `deviceParams.SampleRate = 44100` only. It does **not** call `SetAvailableSampleRatesAsync`. libASPL default `GetAvailableSampleRates()` returns a single range `[nominal, nominal]` — which helps **only until** something sets a broader list or stream rates imply 48 kHz (Apple’s sample plug-in advertises 44.1 **and** 48 kHz). Audit marked DRV-02 **PARTIAL** for this reason.

**How to avoid:**
- After device creation, call `device->SetAvailableSampleRatesAsync({ AudioValueRange{44100, 44100} })` (and align stream physical/virtual rate lists per libASPL `TestOperations` patterns).
- Reject `SetNominalSampleRateAsync` for any rate ≠ 44100 (`CheckNominalSampleRate` should fail).
- Verify with AMS property inspector and Cubase **HW Sample Rate** readout at 44100.
- Add driver unit test or HAL property probe script documenting `kAudioDevicePropertyAvailableNominalSampleRates`.

**Warning signs:**
AMS shows multiple nominal rates for APM44 Bridge.
Cubase project at 44.1 but “HW Sample Rate” shows 48000.

**Phase to address:**
**v1.1 — Driver nominal-rate hardening (DRV-02)**

---

### Pitfall 8: HAL SInt16 stream vs daemon float32 shm (hidden format debt)

**What goes wrong:**
“44100-only” and signing are correct but audio is distorted, quiet, or noisy. Debugging focuses on Cubase while shm carries misinterpreted sample format.

**Why it happens:**
Driver stream uses **SInt16 packed PCM** in `Driver.cpp`; daemon/shm path assumes float32 scale in engine. v1.0 audit tech debt explicitly calls this out.

**How to avoid:**
- Either migrate HAL stream to float32 non-interleaved (match `DEV-02` / daemon) or document fixed-point conversion in `ShmIoHandler` with tested full-scale mapping.
- Block v1.1 sign-off listening tests until format path is validated with 440 Hz tone (not just “sound comes out”).

**Warning signs:**
Harmonic distortion on sine sweep; level meters don’t match DAW output metering.

**Phase to address:**
**v1.1 — Driver nominal-rate hardening** (format alignment); **v1.1 — Cubase / DAW sign-off** (listen test)

---

### Pitfall 9: Cubase 15 routing and rate checklist errors

**What goes wrong:**
- Cubase outputs to Built-in Audio or old BlackHole driver while operator believes HAL path is active.
- Project sample rate 44.1 but device/HW rate 48 kHz → pitch/timing issues blamed on bridge.
- **Studio → Studio Setup → Audio System**: wrong “ASIO Driver” entry (on Mac, Cubase wraps **Core Audio** devices — device must appear in the driver list only if HAL loaded).
- Stereo Out / Control Room not routed to the device outputs in use.
- **Release Driver when Application is in Background** enabled → device released when Cubase loses focus, bridge appears “broken.”
- Export at 48 kHz while project is 44.1 → QA-02 false fail.

**Why it happens:**
Primary sign-off DAW is **Cubase 15** (operator does not have Logic/Ableton). `docs/daw-matrix.md` still emphasizes Logic/Ableton; Cubase-specific steps are not yet first-class. Cubase allows only **one** Core Audio device at a time — no separate output device for AirPods (that’s correct: DAW → APM44 only; AirPods are daemon output).

**How to avoid:**
- Add Cubase 15 section to matrix mirroring Logic rows: Studio Setup → Audio System → select **APM44 Bridge**; project 44100; confirm HW sample rate 44100.
- AMS before Cubase: APM44 @ 44100, AirPods @ 48000 (do not force 44100 on AirPods).
- Disable “Release Driver when in Background” for soak tests.
- QA-02: export with project rate; run `scripts/validate-export-rate.sh --check-file`.
- Restart Cubase after AMS rate or driver install changes.

**Warning signs:**
Cubase driver list has no APM44 entry (HAL load/signing issue, not Cubase bug).
Sound works in QuickTime but not Cubase (different audio stack; Cubase holds exclusive device).

**Phase to address:**
**v1.1 — Cubase / DAW sign-off** (DEV-01, DEV-03, QA-02, 30+ min soak)

---

### Pitfall 10: Skipping reboot / kickstart / first-install sequence

**What goes wrong:**
Signed driver copied correctly but invisible until logout or reboot. Team re-signs repeatedly.

**Why it happens:**
Apple’s Audio Server Plug-in sample notes first install may require reboot; project docs mention kickstart **and** “log out/in or reboot once.”

**How to avoid:**
- Standardize: install → kickstart → `verify-hal-driver.sh` → if fail, reboot once → re-verify before Cubase.
- Document in sign-off runbook, not only in install script echo.

**Warning signs:**
Intermittent enumeration; device appears after reboot without code changes.

**Phase to address:**
**v1.1 — HAL signing & load verification**

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Ad-hoc `install-driver.sh` on dev Mac | Fast HAL iteration | False confidence for v1.1 gate | Local dev only; never for sign-off |
| Notarize app zip without driver zip | One artifact to Apple | HAL still unsigned in field | Never for v1.1 complete |
| BlackHole fallback without UI mode indicator | MVP keeps working | Operator runs wrong path silently | Until app wires `--virtual-device` + clear mode |
| `SampleRate=44100` without available-rates list | Ships DRV-02 “mostly” | Hosts switch to 48 kHz | Never for v1.1 DRV-02 done |
| SInt16 HAL + float daemon | Matches quick libASPL stream setup | Distortion / level bugs | v1.1 listen test must fail this if unfixed |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| **coreaudiod / HAL** | Install to `~/Library` or wrong permissions | `/Library/Audio/Plug-Ins/HAL/`, `root:wheel`, kickstart |
| **Developer ID** | Installer cert on `.driver` | Application cert + hardened runtime |
| **notarytool** | Submit unstaged `.driver` | Zip signed driver; log on failure; staple distributable |
| **Menu bar → daemon** | Only `--output-device` | Add `--virtual-device` when HAL UID present |
| **DAW → HAL → shm → daemon** | DAW to APM44, daemon on BlackHole | Both legs must use virtual-device mode |
| **Cubase 15** | Aggregate device to “fix” routing | Single device: APM44 out; AirPods via daemon only |
| **AMS** | Set AirPods to 44100 | AirPods stay 48000; virtual device stays 44100 |
| **QA-02** | Validate bounce before routing stable | Export after DEV-03 pass; `validate-export-rate.sh` |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Blaming SRC for Cubase buffer glitches | Crackle at low buffer sizes | Separate buffer tuning from 30 min soak | Small buffers + heavy sessions |
| Starting soak before signed HAL stable | False glitch counts | Soak only on production path after DEV-03 | v1.1 QA gate |
| Exclusive device contention | Dropouts when other apps play audio | Quit other DAWs/music apps during matrix | macOS shared Core Audio |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Disabling SIP permanently for “signing” | Weakens machine; masks real signing bugs | Use Developer ID; SIP-off only on dedicated dev kit |
| Over-broad entitlements on driver | Notarization failure; enlarged attack surface | Minimal `APM44Bridge.entitlements` |
| Shipping `sudo install` script without checksum | Tampered HAL path | Distribute signed+notarized pkg or documented hashes |
| Spawning unsigned helper from signed app | Gatekeeper blocks bridge | Embed and sign helper in app bundle |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| App says “Running” but wrong transport | Thinks product is broken | Show mode: “HAL virtual” vs “BlackHole MVP” |
| No guidance when HAL missing | Installs app only; no sound | Detect UID; link to driver install + signing doc |
| Latency copy implies zero delay | Trust loss | Keep honest `~N ms` from metrics (QA-03) |
| Matrix lists Logic/Ableton only | Cubase operator blocked | Cubase 15 column primary in v1.1 |

## "Looks Done But Isn't" Checklist

- [ ] **DRV-02:** `SampleRate=44100` set — verify `kAudioDevicePropertyAvailableNominalSampleRates` returns **only** 44100
- [ ] **DEV-01:** Driver copied — verify enumeration in AMS **and** `apm44-bridge --list-devices` on **macOS 15+** with **Developer ID** build
- [ ] **DEV-03:** Daemon runs — verify **simultaneous** Cubase output to APM44 + `--virtual-device` + AirPods audible
- [ ] **App integration:** Menu bar “Running” — verify process argv includes `--virtual-device` (ps/equivalent)
- [ ] **SHIP:** `notarytool` Accepted — verify **signed HAL load** and optional staple on shipped artifacts
- [ ] **QA-02:** Script exists — verify bounce file with `validate-export-rate.sh --check-file` on Cubase export
- [ ] **QA-01 soak:** Automated 60 s soak passed — verify **30+ min** on HAL path documented with date/commit
- [ ] **Notarization:** App stapled — verify driver intended for install is the **same signed bits** in notarized zip

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Ad-hoc HAL on macOS 15 | LOW | Re-sign Developer ID; reinstall; kickstart; reboot if needed |
| Wrong notarization container | LOW | Read `notarytool log`; fix signing; resubmit zip |
| App without `--virtual-device` | LOW | Patch `BridgeProcessManager`; restart bridge |
| DRV-02 incomplete | MEDIUM | `SetAvailableSampleRatesAsync`; retest AMS + Cubase HW rate |
| Cubase wrong device | LOW | Studio Setup switch; restart Cubase; re-run matrix row |
| Format SInt16/float mismatch | MEDIUM–HIGH | Align HAL ASBD + shm handler; re-validate tone test |

## Pitfall-to-Phase Mapping

Recommended v1.1 phase split (from PROJECT.md milestone scope):

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Ad-hoc HAL / AMFI reject | **HAL signing & load** | Signed driver enumerates on macOS 15+; no AMFI errors in log |
| Wrong cert / signing order | **HAL signing & load** | `codesign --verify --deep --strict` on driver + inner binary |
| Notarization container/staple | **HAL signing & load** | `notarytool submit` Accepted; staple validate on shipped app/driver |
| App missing `--virtual-device` | **App virtual-device wiring** | Spawn argv includes flag when HAL UID present |
| Hotplug / unsigned helper | **App virtual-device wiring** | Hotplug restart + release app bundle spawn signed binary |
| DRV-02 nominal list | **Driver 44100-only hardening** | Property probe; AMS single rate; Cubase HW 44100 |
| SInt16 vs float32 | **Driver 44100-only hardening** | 440 Hz tone clean; levels match DAW |
| Cubase routing / QA-02 | **Cubase sign-off & soak** | Matrix rows pass; export script 44100; 30+ min soak log |
| Reboot/kickstart | **HAL signing & load** | `verify-hal-driver.sh` after install |

## Sources

| Source | Confidence | Used for |
|--------|------------|----------|
| `.planning/PROJECT.md` (v1.1 milestone) | HIGH | Scope, gates, Cubase-primary |
| `.planning/milestones/v1.0-MILESTONE-AUDIT.md` | HIGH | Gaps: DRV-02, app wiring, signing |
| `Driver/src/Driver.cpp`, `BridgeProcessManager.swift` | HIGH | Current implementation risks |
| `third_party/libASPL/src/Device.cpp` | HIGH | Default vs explicit available sample rates |
| [Creating an Audio Server Driver Plug-in](https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in) | HIGH | HAL install path; sample rates |
| [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues) | HIGH | Cert types, containers |
| [Melatonin — code sign & notarize macOS audio plugins](https://melatonin.dev/blog/how-to-code-sign-and-notarize-macos-audio-plugins-in-ci/) | MEDIUM | zip/submit/staple workflow |
| [tympan-aspl — macOS 15 AMFI / Developer ID](https://github.com/penta2himajin/tympan-aspl) | MEDIUM | Ad-hoc HAL rejection on macOS 15 |
| [Cubase 15 — Selecting an audio driver](https://www.steinberg.help/r/cubase-artist/15.0/en/cubase_nuendo/topics/setting_up/setting_up_audio_driver_selecting_t.html) | MEDIUM | Studio Setup flow |
| Steinberg forums (Core Audio wrapper on Mac) | MEDIUM | Single-device constraint |

---
*Pitfalls research for: APM44 Bridge v1.1 Production Sign-Off*
*Researched: 2026-06-01*
