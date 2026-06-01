# Pitfalls Research

**Domain:** macOS real-time audio bridge / virtual driver
**Researched:** 2026-06-01
**Confidence:** HIGH

## Critical Pitfalls

### 1. Clock drift without variable-ratio SRC

**Warning signs:** Works for 5–10 minutes, then occasional clicks; buffer fill trends up or down over time; latency slowly increases.

**Prevention:** Ring buffer + target fill controller adjusting `src_ratio` each output block; cap PPM correction (±500 ppm).

**Phase:** Phase 2 (bridge engine hardening)

---

### 2. malloc / locks / logging in IOProc

**Warning signs:** Random glitches under CPU load; spikes in callback duration in Instruments.

**Prevention:** Preallocate all buffers at `prepare()`; lock-free SPSC ring; defer logs to background thread via lock-free trace buffer.

**Phase:** Phase 1–2

---

### 3. Trying to set AirPods nominal rate to 44100

**Warning signs:** `AudioObjectSetPropertyData` fails or DAW reports rate mismatch; MIDI Setup shows 48 kHz only on hardware.

**Prevention:** Accept 48 kHz on physical device; SRC in bridge only.

**Phase:** Phase 0 (design) — do not regress

---

### 4. Aggregate / Multi-Output device “shortcut”

**Warning signs:** Unstable latency; DAW sees conflicting master clocks; impossible to report single latency number.

**Prevention:** Single virtual 44.1 sink + dedicated daemon output to AirPods.

**Phase:** N/A — architectural

---

### 5. GPL BlackHole embedding

**Warning signs:** Legal review flags; static linking of GPL code in proprietary app.

**Prevention:** MVP documents external BlackHole install; production ships own ASPL (MIT stack via libASPL).

**Phase:** Phase 1 MVP vs Phase 4 driver

---

### 6. HAL plug-in signing / load failures (macOS 15+)

**Warning signs:** Device never appears; `coreaudiod` rejects bundle; AMFI errors in Console.

**Prevention:** Developer ID sign `.driver`; test load on target OS; document dev SIP workflow only for local unsigned iteration.

**Phase:** Phase 4

---

### 7. Driver doing too much (SRC, hardware open)

**Warning signs:** Driver crashes take down all Core Audio; hard to debug; certification nightmare.

**Prevention:** Driver = buffer transport + properties; daemon = SRC + AirPods client.

**Phase:** Phase 4

---

### 8. Fixed block-size assumption (147→160)

**Warning signs:** Glitches when DAW uses 32/64/512 buffer sizes; partial frames at block boundaries.

**Prevention:** Streaming SRC with leftover sample state; unit tests across buffer sizes.

**Phase:** Phase 2

---

### 9. Swift/UI on audio thread

**Warning signs:** Rare crashes; priority inversion.

**Prevention:** Atomics for config snapshot; UI updates on main queue only.

**Phase:** Phase 3

---

### 10. Pro Tools single-engine expectation (v1 scope creep)

**Warning signs:** Users expect I/O on one device; v1 only fixes output monitoring path.

**Prevention:** Document Logic/Ableton path for v1; track PT unified engine as v2 (PT-01).

**Phase:** Requirements / docs

## Phase Mapping Summary

| Phase focus | Pitfalls to address |
|-------------|---------------------|
| Phase 1 MVP routing | #3, #4, #6 (N/A), basic #2 |
| Phase 2 SRC/drift | #1, #8 |
| Phase 3 App | #9 |
| Phase 4 Driver | #5, #6, #7 |
