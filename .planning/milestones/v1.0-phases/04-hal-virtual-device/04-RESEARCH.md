# Phase 4 Research: HAL Virtual Device

**Researched:** 2026-06-01  
**Confidence:** HIGH (Apple HAL + libASPL docs); MEDIUM (first-install HAL load without Developer ID)

## Decision Summary

| Topic | Choice | Rationale |
|-------|--------|-----------|
| HAL stack | **libASPL v3.1.2** (git submodule) | MIT; C++17; official examples for virtual output device |
| Device identity | UID `com.niko.apm44.bridge.device`, name **APM44 Bridge** | Per 04-CONTEXT |
| Sample rates | **44100 Hz only** in nominal rates | Production contract; DAW lies upstream |
| IPC | POSIX `shm_open` + mmap SPSC ring in `Shared/` | Apple cross-arch plug-in guidance; same process layout for driver + daemon |
| Shm name | `/apm44_bridge_ring` (leading slash for `shm_open`) | Single global segment for MVP |
| Driver RT path | `memcpy` planar float → mmap ring only | No malloc/locks/SRC in IOProc |
| Daemon input | `--virtual-device` → pop shm in output IOProc path | Avoid second HAL input client; reuse existing SRC/drift pipeline |
| Build | **CMake** `Driver/` + root `add_subdirectory` | Reproducible CI compile of plugin binary; Xcode signing deferred Phase 5 |
| Install | `scripts/install-driver.sh` → `/Library/Audio/Plug-Ins/HAL/` | Dev workflow; sudo documented |

## Shm Layout (v1)

```
ShmRingHeader (cache-line padded where practical)
  magic: 'APM4'
  version: 1
  capacity_frames: uint32 (power of 2)
  sample_rate: 44100
  channels: 2
  write_index: atomic<uint64>  (driver producer)
  read_index: atomic<uint64>   (daemon consumer)
  daemon_ready: atomic<uint32>  (optional handshake)
  driver_generation: atomic<uint32>

Planar samples: float[channel][capacity] interleaved as L/R planes in shm
  offset = align(sizeof(ShmRingHeader), 64)
  size = capacity * 2 * sizeof(float)
```

**Producer (driver):** push frames like `PlanarRingBuffer::push` — drop oldest on overrun (bounded).  
**Consumer (daemon):** pop into internal `PlanarRingBuffer` or direct pop in `feedFromVirtualDevice()`.

## libASPL Integration

- Submodule: `third_party/libASPL` @ tag **v3.1.2**
- `cmake/LibASPL.cmake`: `add_subdirectory(third_party/libASPL)` with tests disabled
- Driver target links `libASPL` static, produces `APM44Bridge.driver` bundle via `MACOSX_BUNDLE` + `BUNDLE_EXTENSION driver`

## Gaps (explicit for VERIFICATION)

1. **HAL load without Developer ID** — may require SIP-off or user approval on macOS 15+; not solved in Phase 4
2. **Full `DoIOOperation` wiring** — skeleton may use stream callback stub until manual QA with coreaudiod
3. **Menu bar** — still spawns BlackHole path until Phase 5 passes `--virtual-device`
4. **Latency property** — driver-reported latency not calibrated in Phase 4

## References

- [Creating an Audio Server Driver Plug-in](https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in)
- [Cross-Architecture Plug-in Support](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/64bitPorting/Cross-ArchitecturePluginSupport/Cross-ArchitecturePluginSupport.html)
- [libASPL](https://github.com/gavv/libASPL) — examples/minimal driver patterns
