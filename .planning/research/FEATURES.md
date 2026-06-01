# Features Research

**Domain:** macOS DAW monitoring bridge (44.1 virtual → 48 kHz hardware)
**Researched:** 2026-06-01
**Confidence:** HIGH

## Table Stakes (users expect these or the product fails)

| Feature | Complexity | Notes |
|---------|------------|-------|
| Stereo virtual output at stated nominal rate (44.1 kHz) | Medium | Must match DAW project rate without lying about exports |
| Stable long-play monitoring (30+ min) | High | Drift control is the hard part |
| Device appears in DAW output list | Medium | Clear naming: **APM44 Bridge** |
| Physical output to selected hardware (AirPods USB-C) | Medium | Hotplug recovery |
| Float32 PCM, 2ch | Low | Standard DAW format |
| Honest latency reporting | Low | Modes, not “zero latency” marketing |
| Start/stop bridge without DAW crash | Medium | Clean Core Audio graph teardown |

## Differentiators (competitive advantage)

| Feature | Complexity | Notes |
|---------|------------|-------|
| 44.1-only virtual device (no rate confusion) | Medium | Unlike generic loopback drivers exposing many rates |
| Purpose-built 44.1→48 drift-aware SRC | High | Ratio 160/147 with PPM trim |
| Latency/quality presets tied to buffer + SRC tier | Medium | Low / Balanced / Safe |
| Buffer fill + glitch meter in menu bar | Low | Trust for producers |
| Single-product mental model (“DAW thinks 44.1”) | Low | Documentation + UX |

## Anti-Features (deliberately do NOT build)

| Anti-Feature | Why Avoid |
|--------------|-----------|
| Multi-Output / Aggregate routing | Unpredictable clock domains and latency |
| Forcing hardware to 44.1 kHz | Impossible on fixed 48 kHz USB-C endpoint |
| In-driver sample rate conversion | Driver should stay thin; RT risk |
| GPL BlackHole embedded in commercial binary | License contamination |
| “Zero latency” claims | Physically false for SRC + buffering |
| Full Pro Tools unified engine in v1 | Large scope; defer to v2 |

## Dependencies Between Features

```
Virtual device (44.1) ──► Bridge capture ──► Ring buffer ──► SRC ──► AirPods @ 48
                              ▲                    │
                              └── Drift controller ┘
Menu bar UI ──► config (latency mode, device ID) ──► non-RT control channel
```

## Category Map for Requirements

1. **Virtual device & DAW** — DEV-*
2. **Bridge engine** — ENG-*
3. **MVP BlackHole path** — MVP-*
4. **Production driver** — DRV-*
5. **Application & UX** — APP-*
6. **Validation** — QA-*

## v1 vs v2 Split

| v1 | v2 |
|----|-----|
| BlackHole MVP + production ASPL | Pro Tools unified virtual engine |
| Menu bar + 3 latency modes | Installer/notarization automation |
| AirPods USB-C wired path | Bluetooth path (if ever) |
