# Phase 9: Cubase Sign-Off & Soak — Operator Verification

> **Human-only.** Agent cannot run Cubase. Complete on sign-off Mac with signed HAL + menu bar app.

## Automated pre-checks

```bash
bash scripts/verify-hal-driver.sh
bash scripts/verify-devices.sh
bash scripts/validate-export-rate.sh --instructions
cmake --build build && ctest --test-dir build --output-on-failure
```

## Operator checklist

See [docs/cubase-soak.md](../../../docs/cubase-soak.md) and [docs/daw-matrix.md](../../../docs/daw-matrix.md).

| Requirement | Evidence | Pass? |
|-------------|----------|-------|
| DEV-03 Cubase 15 @ 44100 → APM44 Bridge → AirPods | Listening notes | |
| DEV-04 AirPods @ 48000 during HAL path | AMS screenshot or afinfo | |
| QA-01 30+ min soak | [cubase-soak.md](../../../docs/cubase-soak.md) evidence block | |
| QA-02 export @ 44100 | `validate-export-rate.sh --check-file` exit 0 | |

## Sign-off

| Field | Value |
|-------|-------|
| Operator | |
| Date | |
| macOS | |
| Cubase | 15.x |
| Overall | pass / fail |

When all rows pass, mark Phase 9 complete in `.planning/STATE.md`.
