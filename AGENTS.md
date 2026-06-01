<!-- GSD:project-start source:PROJECT.md -->
## Project

**APM44 Bridge**

APM44 Bridge is a macOS audio product that lets DAW users (Logic, Ableton, Pro Tools, etc.) run **44.1 kHz** sessions while monitoring through **AirPods Max USB-C at 48 kHz**. The DAW sees a virtual Core Audio output device named **APM44 Bridge** (2ch, Float32, 44,100 Hz). A user-space bridge daemon resamples 44.1 → 48, handles clock drift, and plays to the physical AirPods endpoint. The headphones are **not** retuned to 44.1 kHz—the software lies upstream to the DAW, not downstream to the hardware.

**Core Value:** A producer can set session/project rate to **44.1 kHz**, select **APM44 Bridge** as output, and hear stable, low-glitch monitoring on AirPods Max USB-C at **48 kHz** for long sessions—without changing exports, stems, plug-in oversampling assumptions, or project metadata.

### Constraints

- **Platform**: macOS only — Core Audio, HAL Audio Server Plug-in for production virtual device
- **Driver pattern**: Audio Server Driver Plug-in (not AudioDriverKit for virtual device per Apple guidance)
- **Formats**: Float32, non-interleaved, 2 channels; virtual device **44100 only** in production driver
- **Real-time**: Audio callbacks — no malloc, locks, logging, Swift ARC churn, Obj-C messaging, file I/O, device enumeration, UI mutation
- **Licensing**: BlackHole is GPL-3.0 — do not fork/ship inside closed app without compliance strategy
- **Hardware**: AirPods Max USB-C fixed 48 kHz endpoint; bridge must not open AirPods from inside the driver
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core platform & language split
| Technology | Version / target | Purpose | Why |
|------------|------------------|---------|-----|
| **macOS SDK** | Xcode **16.x** (minimum **15.4**), `MACOSX_DEPLOYMENT_TARGET=14.0` | Build, sign, notarize | HAL `.driver` bundles, `codesign`, and `notarytool` are first-class in Xcode; Apple’s Audio Server Plug-in sample is Xcode-oriented |
| **C++** | **C++20** (`BridgeDaemon`, `Shared`, RT engine) | Real-time bridge, SRC, ring buffer, drift | Matches PROJECT constraint: no malloc/locks/logging in audio callbacks; keeps RT path out of Swift/Obj-C runtime |
| **Swift** | **5.10+** (toolchain bundled with Xcode 16) | Menu bar app only | `MenuBarExtra` + SwiftUI for status, device picker, latency presets; **no audio callbacks in Swift** |
| **Objective-C++** | Thin glue only | XPC/IPC to daemon, optional AppKit bridges | Use sparingly at App ↔ daemon boundary |
### Virtual device — production (`APM44Bridge.driver`)
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Audio Server Driver Plug-in** (HAL) | Core Audio `AudioServerPlugIn.h` (system) | Virtual **APM44 Bridge** @ 44.1 kHz, 2ch Float32 | Apple documents virtual devices via Audio Server Plug-in; **AudioDriverKit is for physical devices only** ([Creating an audio device driver](https://developer.apple.com/documentation/AudioDriverKit/creating-an-audio-device-driver)) |
| **Apple sample** | “Creating an Audio Server Driver Plug-in” (C) | Starting point / compliance checklist | Official minimal plug-in: 44.1/48 kHz, 2ch float, install under `/Library/Audio/Plug-Ins/HAL/` ([doc](https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in)) |
| **libASPL** | Track **main** or latest release tag from [gavv/libASPL](https://github.com/gavv/libASPL) (MIT) | C++17 shim over `AudioServerPlugInDriverInterface` | Cuts CF/HAL boilerplate; maps properties to C++ virtuals; used in production drivers (e.g. roc-vad). **Pin a git SHA** in repo — do not float `main` in release builds |
| **Driver implementation language** | **C++17** in `.driver` bundle | `DoIOOperation` / ring handoff | Same language family as daemon; driver stays “boring” (fixed 44100 Hz, copy-only in RT) |
### MVP virtual sink (external — not shipped)
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **BlackHole 2ch** | **v0.6.1** (2025-02-08) | DAW → 44.1 loopback sink before custom driver | De-risks SRC/drift/routing; user installs separately. GPL-3.0 — **do not vendor or statically link** ([ExistentialAudio/BlackHole](https://github.com/ExistentialAudio/BlackHole)) |
| **Existential Audio license** | Commercial if ever bundling | Only if product policy changes | README: non-GPL apps need a separate license from Existential Audio |
### Bridge daemon — Core Audio clients
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Core Audio HAL** | System framework | Device discovery, format negotiation, I/O | Standard for low-latency device-to-device bridge on macOS |
| **`AudioDeviceCreateIOProcID` / `AudioDeviceStart`** | macOS 10.5+ (current API) | Input @ 44.1 kHz, output @ 48 kHz | Replaces deprecated `AudioDeviceAddIOProc`; supports multiple registrations ([TN2223](https://developer.apple.com/library/archive/technotes/tn2223/_index.html)) |
| **`AudioObjectGetPropertyData` / `AudioObjectSetPropertyData`** | System | Device UID lookup, stream format, nominal rate | Modern property API (avoid deprecated `AudioDeviceGetProperty`) |
| **Optional: `kAudioUnitSubType_HALOutput`** | AudioToolbox | Alternate I/O path | Valid for bring-up; **prefer raw HAL IOProcs** for a symmetric in/out bridge with one drift controller |
### Real-time audio engine (`BridgeDaemon` + `Shared`)
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Lock-free SPSC ring** | Custom (C++20) | Jitter buffer between input IOProc, SRC, output IOProc | RT-safe; no mutex in callback; target fill 10–20 ms per PROJECT |
| **Drift controller** | Custom | PPM on consumption (`src_ratio` or read pointer), ±500 ppm cap | 48000/44100 = 160/147 is nominal only; clocks drift |
| **Logging / metrics** | **spdlog** or minimal async queue | Non-RT thread only | Never log from IOProc |
| **IPC to UI** | **XPC** (Swift app ↔ daemon) | Latency mode, device selection, state | UI never touches HAL from RT threads |
### Sample-rate conversion
| Phase | Technology | Version | Purpose | Why |
|-------|------------|---------|---------|-----|
| **MVP / POC** | **AudioToolbox `AudioConverter`** (C API) | System | Fixed **44100 → 48000** conversion | Same family as `AVAudioConverter`; usable entirely from C++ daemon ([TN3136](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions) describes streaming pattern — implement with **persistent** converter instance, never per-buffer `AudioConverterNew`) |
| **MVP alternative (UI-only experiments)** | **AVAudioConverter** | AVFAudio (system) | Spike in Swift playground only | Fine for one-off tests; **do not** put in IOProc or daemon RT path |
| **Production** | **libsamplerate** (“Secret Rabbit Code”) | **0.2.2** ([Homebrew](https://formulae.brew.sh/formula/libsamplerate), [libsndfile/libsamplerate](https://github.com/libsndfile/libsamplerate)) | Streaming `src_process()` + variable `src_ratio` / `src_set_ratio()` | Official API for **time-varying** ratio between calls ([api_misc](https://libsndfile.github.io/libsamplerate/api_misc.html), [api_full](https://libsndfile.github.io/libsamplerate/api_full.html)); matches drift requirement |
| **Production quality preset** | `SRC_SINC_MEDIUM_QUALITY` (default) / `SRC_SINC_BEST_QUALITY` (Safe mode) | — | Quality vs CPU | Medium ≈ 96% bandwidth; Best ≈ 97% ([FAQ](http://www.mega-nerd.com/SRC/faq.html)) |
### Menu bar application
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **SwiftUI** | iOS/macOS 14+ SDK | Settings, status, meters (non-RT) | Native menu bar UX |
| **`MenuBarExtra`** | macOS 13+ (ok on 14+ target) | Menu bar shell | Standard pattern for audio utilities |
| **AppKit** | As needed | `NSStatusItem` fallback, permissions UX | Only if `MenuBarExtra` limits are hit |
| **Distribution** | `.app` + **Developer ID** + notarization | User install | Same signing story as daemon; staple ticket |
### Build, packaging, CI
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Xcode** | **16.x** primary | Multi-target workspace: `APM44Bridge.driver`, `apm44-bridge` (daemon), `APM44 Bridge.app` | `.driver` bundle layout, embedded `Info.plist`, `CFPlugInFactories`, copy-files build phase to `Wrapper/PlugIns` or install script |
| **CMake** | **3.28+** | **Optional** — libsamplerate, unit tests, fuzz-free RT tests | Use `add_subdirectory(libsamplerate)` + `ExternalProject` or FetchContent; **generate Xcode project** (`cmake -G Xcode`) or build static lib consumed by Xcode target. **Do not** make CMake the sole owner of `.driver` signing — Xcode should own install/sign |
| **swift-format / clang-format** | Project-pinned | Style | Separate C++ and Swift format configs |
### Code signing & distribution (HAL + app)
| Step | Tool / cert | Notes |
|------|-------------|--------|
| Sign `.driver` | **Developer ID Application** + Hardened Runtime | `codesign --force -s "Developer ID Application: …" --timestamp --options runtime APM44Bridge.driver` ([Melatonin guide](https://melatonin.dev/blog/how-to-code-sign-and-notarize-macos-audio-plugins-in-ci/)) |
| Sign `.app` / daemon | Same cert | All shipped binaries hardened |
| Notarize | **`xcrun notarytool submit`** | Submit **zip/dmg/pkg** container, not raw loose binary ([Apple workflow](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)) |
| Staple | **`xcrun stapler staple`** | Offline Gatekeeper acceptance |
| Install driver | `sudo cp -R APM44Bridge.driver /Library/Audio/Plug-Ins/HAL/` + `chown root:wheel` | HAL plug-ins load from this path ([AudioServerPlugIn.h](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.11.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioServerPlugIn.h)) |
| Reload HAL | `sudo launchctl kickstart -k system/com.apple.audio.coreaudiod` | Prefer kickstart over legacy stop/start; **reboot** still required for some first-install cases per Apple sample |
| macOS 15+ | Developer ID **required** for full load | Ad-hoc signed HAL bundles may fail AMFI before plug-in code runs ([tympan-aspl notes](https://github.com/penta2himajin/tympan-aspl)) — budget Apple Developer Program early |
## Alternatives Considered
| Category | Recommended | Alternative | Why not (for APM44) |
|----------|-------------|-------------|---------------------|
| Virtual device API | Audio Server Plug-in (C/C++ + libASPL) | **AudioDriverKit** + Driver Extension | Apple: virtual devices → ASPL; DriverKit is for **physical** hardware |
| Virtual device API | ASPL | **Core Audio Tap (`CATap`)** (macOS 14.2+) | Tap captures/monitor paths; does **not** present a 44.1 kHz **output device** to the DAW — wrong abstraction |
| HAL boilerplate | libASPL (MIT) | Raw C Apple sample only | More code; acceptable for minimal PoC, slower to production |
| HAL boilerplate | libASPL | **tympan-aspl** (Rust) | Strong for Rust teams; splits stack (Rust driver + C++ daemon) — unnecessary complexity |
| MVP sink | BlackHole 2ch (external) | **Soundflower** (abandoned) | Unmaintained; security/compatibility risk |
| MVP sink | BlackHole | **Aggregate Device** | Explicitly out of scope in PROJECT |
| Production SRC | **libsamplerate 0.2.2** | **libsoxr** (SOXR_VR) | SoXR VR needs careful max I/O ratio at `soxr_create`; misconfiguration causes **clicks** ([SoXR thread](https://sourceforge.net/p/soxr/discussion/general/thread/9f2d0a1b/)). Higher latency (~20 ms HQ 44.1↔48). libsamplerate’s `src_ratio` smoothing matches drift control |
| Production SRC | libsamplerate | **Accelerate vDSP** | No high-quality arbitrary-ratio SRC |
| MVP SRC | AudioToolbox `AudioConverter` | **libsamplerate from day one** | Valid shortcut — slightly more work upfront but one SRC path; **acceptable override** if team wants single converter early |
| MVP SRC | AudioConverter | **AVAudioEngine** | Device hot-swap pain; ARC/logging risk if misused |
| Bridge I/O | HAL `AudioDeviceIOProc` | **AUHAL** × 2 | Two IO procs; harder to unify drift; TN2091 warns against direct AU-to-AU wiring |
| Build | Xcode-primary | **CMake-only** | Poor `.driver` signing/notarization story; weak `CFPlugIn` bundle ergonomics |
| Build | Xcode + CMake for libs | **Homebrew-only deps** | Non-reproducible user machines for production binaries |
| IPC | shm + SPSC | **Unix domain socket audio** | Extra copies; latency; not RT-friendly |
| Menu bar | SwiftUI `MenuBarExtra` | **Electron / Tauri** | Violates native audio tool expectations; larger attack surface |
## What NOT to Use
| Do not use | Reason |
|------------|--------|
| **AudioDriverKit** for APM44 virtual device | Apple directs virtual devices to Audio Server Plug-in |
| **Kernel extensions / legacy IOAudioFamily** | Deprecated path; not needed for user-space HAL plug-in |
| **Bundling or forking BlackHole** in closed-source product | GPL-3.0; requires GPL app or commercial license from Existential Audio |
| **Aggregate / Multi-Output Device** as primary architecture | Out of scope; brittle UX in Audio MIDI Setup |
| **`kAudioDevicePropertyNominalSampleRate` on AirPods** to force 44.1 | Hardware reports 48 kHz; fighting nominal rate breaks monitoring model |
| **soxr SOXR_VR** as first production SRC | Tuning burden and click risk on ratio steps; libsamplerate already documents variable `src_ratio` |
| **`src_simple()`** | Not for streaming; causes glitches between buffers ([FAQ](http://www.mega-nerd.com/SRC/faq.html)) |
| **Per-buffer `AudioConverterNew` / new `AVAudioConverter` per block** | Destroys converter state → corruption/stutter ([Stack Overflow / TN3136 pattern](https://stackoverflow.com/questions/64553738/avaudioconverter-corrupts-data)) |
| **malloc, mutexes, `NSLog`, Swift, Obj-C messaging in IOProc** | PROJECT RT constraints; glitches and priority inversion |
| **Opening AirPods from inside `.driver`** | Driver runs in `coreaudiod`; wrong process; keep I/O in user daemon |
| **JACK** (unless explicit future scope) | Extra daemon dependency; not DAW “select output device” workflow |
| **Rust for entire stack** (default) | No project requirement; splits expertise unless team standardizes on tympan-aspl |
| **Ad-hoc signed HAL plug-in for release** | macOS 15+ may reject before enumeration ([community validation](https://github.com/penta2himajin/tympan-aspl)) |
| **`altool` notarization** | Deprecated; use `notarytool` |
## Version Compatibility
| Component | Minimum | Tested / recommended | Notes |
|-----------|---------|----------------------|--------|
| macOS | **14.0** | **14.x, 15.x** | PROJECT constraint; re-test HAL load on **15** with Developer ID |
| Xcode | **15.4** | **16.x** | Swift 5.10+, current SDK |
| BlackHole (MVP) | 0.6.0 | **0.6.1** | [Releases](https://github.com/ExistentialAudio/BlackHole/releases) |
| libsamplerate | 0.2.2 | **0.2.2** | Pin tag; BSD-2-Clause |
| libASPL | — | **pin git SHA** | MIT; API stable but pin for reproducibility |
| Logic / Ableton / Pro Tools | — | Latest + one N-1 | DAW QA matrix (not build deps) |
## Installation (developer bootstrap)
# macOS dependencies (dev only)
# BlackHole MVP (user-facing install doc — not bundled)
# Download BlackHole 2ch v0.6.1 from Existential Audio / GitHub releases
# Set sample rate 44100 Hz in Audio MIDI Setup
# libsamplerate as submodule (production)
# Xcode: open APM44Bridge.xcworkspace, targets Driver + BridgeDaemon + App
# Driver install (unsigned local dev — SIP-disabled machine only):
# sudo cp -R build/Release/APM44Bridge.driver /Library/Audio/Plug-Ins/HAL/
# sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
## Sources
| Source | Confidence | Used for |
|--------|------------|----------|
| [Creating an Audio Server Driver Plug-in](https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in) | HIGH | HAL virtual device, 44.1/48 kHz sample |
| [Creating an audio device driver (AudioDriverKit)](https://developer.apple.com/documentation/AudioDriverKit/creating-an-audio-device-driver) | HIGH | Do not use DriverKit for virtual device |
| [TN2223 Deprecated HAL APIs](https://developer.apple.com/library/archive/technotes/tn2223/_index.html) | HIGH | `AudioDeviceCreateIOProcID` |
| [TN3136 AVAudioConverter / sample rate conversion](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions) | HIGH | Persistent converter, streaming pattern |
| [libsamplerate API — variable `src_ratio`](https://libsndfile.github.io/libsamplerate/api_misc.html) | HIGH | Production drift SRC |
| [BlackHole README / releases](https://github.com/ExistentialAudio/BlackHole) | HIGH | MVP v0.6.1, GPL, no bundle |
| [libASPL](https://github.com/gavv/libASPL) | MEDIUM | MIT HAL C++ shim |
| [Cross-Architecture Plug-in Support (mmap + lock-free ring)](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/64bitPorting/Cross-ArchitecturePluginSupport/Cross-ArchitecturePluginSupport.html) | HIGH | shm/ring pattern |
| [Melatonin — code sign & notarize audio plugins](https://melatonin.dev/blog/how-to-code-sign-and-notarize-macos-audio-plugins-in-ci/) | MEDIUM | Developer ID + notarytool workflow |
| [tympan-aspl — macOS 15 signing](https://github.com/penta2himajin/tympan-aspl) | MEDIUM | Ad-hoc vs Developer ID on HAL load |
| [SoXR variable-rate discussion](https://sourceforge.net/p/soxr/discussion/general/thread/9f2d0a1b/) | MEDIUM | Why not default to soxr VR for drift |
| Homebrew `libsamplerate` 0.2.2 | HIGH | Version pin |
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.Codex/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-Codex-profile` -- do not edit manually.
<!-- GSD:profile-end -->
