# Phase 8 Live Verification Checklist

**Build ID under test:** `0.1.1+543ca08019de`  
**Date:** 2026-06-11  
**Operator:** _pending human verification_

Manual Cubase/AirPods steps require hardware and a logged-in session. Automated portions below were executed by the phase executor.

---

## Automated (executor-run)

| Step | Command | Result | Notes |
|------|---------|--------|-------|
| Full CI | `bash scripts/ci.sh` | **PASS** | Native ctest + 41 Swift tests |
| HAL driver script | `bash scripts/verify-hal-driver.sh` | **WARN/FAIL** | Installed HAL SHA differs from build; ring `driver_build_id` stale vs helper |
| Installed sync (dry-run) | `bash scripts/verify-installed-sync.sh --dry-run` | **PASS** | `repo_build_id` == `helper_build_id` after embed |
| Shm status | `apm44-bridge --shm-status` | **PASS** | Ring active; `helper_build_id=0.1.1+543ca08019de` |
| Embed helper | `bash scripts/embed-daemon-in-app.sh` | **PASS** | Release app bundle updated |

**Reinstall driver before live soak** (sudo required):

```bash
cmake --build build --target APM44Bridge
bash scripts/install-driver.sh
# Reload Core Audio or reboot if device list does not refresh
bash scripts/verify-hal-driver.sh
```

---

## Hotplug smoke (manual)

1. Quit any old APM44 Bridge copies (DMG or stale installs).
2. Launch `build/Release/APM44 Bridge.app` (or installed copy after embed).
3. Select USB-C AirPods output → **Start Bridge** → confirm metrics in menu.
4. Disconnect USB-C AirPods → expect reconnect banner.
5. Reconnect AirPods → confirm audio resumes **without** Cubase restart.

| Check | Pass | Fail | Notes |
|-------|------|------|-------|
| Disconnect detected | ☐ | ☐ | |
| Reconnect without DAW restart | ☐ | ☐ | |

---

## Cubase HAL smoke (manual)

1. Cubase 15, **44.1 kHz** project.
2. Output routed to **APM44 Bridge** (HAL virtual device).
3. Play **2+ minutes** — no silence wedge, metrics stream active.
4. While running: `apm44-bridge --shm-status` — `helper_build_id` matches embedded helper.

| Check | Pass | Fail | Notes |
|-------|------|------|-------|
| Audio plays 2+ min | ☐ | ☐ | |
| No silence wedge | ☐ | ☐ | |
| shm-status IDs match | ☐ | ☐ | |

---

## Cubase soak (manual, 15+ min)

1. Continue playback **15+ minutes**.
2. Watch metrics for xruns / recoveries.
3. Note any coreaudiod reload or hotplug during soak.

| Check | Pass | Fail | Notes |
|-------|------|------|-------|
| 15+ min stable | ☐ | ☐ | |
| xruns acceptable | ☐ | ☐ | |

---

## Evidence table

| Date | Build ID | Hotplug | Cubase smoke | Soak | Operator | Notes |
|------|----------|---------|--------------|------|----------|-------|
| 2026-06-11 | 0.1.1+543ca08019de | pending | pending | pending | — | Automated CI/sync green; HAL install stale |
| | | ☐ | ☐ | ☐ | | |

**Resume signal:** Type `approved` with evidence notes after completing manual rows, or describe failures to fix.
