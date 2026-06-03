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
| DEV-03 Cubase 15 @ 44100 -> APM44 Bridge -> AirPods | Operator confirmed live monitoring works after the dropout fix on 2026-06-03. | Pass (operator-confirmed) |
| DEV-04 AirPods @ 48000 during HAL path | Operator marked the AirPods/HAL-path check done on 2026-06-03; exact AMS screenshot/`afinfo` output was not supplied in chat. | Pass (operator-confirmed) |
| QA-01 30+ min soak | Operator reported the Cubase soak done on 2026-06-03. | Pass (operator-confirmed) |
| QA-02 export @ 44100 | Operator reported the export validation done on 2026-06-03; exact `validate-export-rate.sh --check-file` output was not supplied in chat. | Pass (operator-confirmed) |

## Sign-off

| Field | Value |
|-------|-------|
| Operator | Niko |
| Date | 2026-06-03 |
| macOS | 26.5 |
| Cubase | 15.x |
| Overall | Pass (operator-confirmed) |

Phase 9 is complete based on operator confirmation.
