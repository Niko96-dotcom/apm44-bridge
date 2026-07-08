# Multi-Harness Soak Runs

Live soak runs prove Ultimate De-Slop outside the deterministic fake-CLI CI fixture.

## How to record a soak

1. Pick a small messy target repo (or the local fixture pattern under `/tmp`).
2. Run doctor first:

```sh
export DESLOP_HARNESS=<codex|claude|cursor|opencode|...>
export DESLOP_MODEL=<model-id>   # e.g. composer-2.5 for cursor
scripts/deslop-doctor.py
```

3. Initialize and loop:

```sh
scripts/deslop-init.sh
scripts/deslop-status.py
scripts/deslop-loop.sh --max-iterations 5 --priority P0,P1
```

4. Capture before/after:

| Field | Value |
| --- | --- |
| Date | YYYY-MM-DD |
| Harness | |
| Model | |
| Target repo | |
| Before score | |
| After score | |
| Verified IDs | |
| Stop reason | |
| Needs human | |
| Notes / artifact path | |

Store artifacts under a local path such as `artifacts/deslop-soak/<date>-<harness>/` with:

- `before-status.json` / `after-status.json`
- `findings.jsonl`
- `state.json`
- optional source diff for the main repaired files

## Template matrix

| Harness | Model | Status | Last soak | Notes |
| --- | --- | --- | --- | --- |
| Codex | (pin with `DESLOP_MODEL`) | pending live soak | | Default adapter |
| Claude | (pin with `DESLOP_MODEL`) | pending live soak | | |
| Cursor | `composer-2.5` | pending live soak | | Requires `CURSOR_API_KEY` or `agent login` |
| OpenCode | (pin with `DESLOP_MODEL`) | pending live soak | | |
| Deterministic fake Codex | n/a | covered in CI | `tests.test_harness.HarnessTests.test_deterministic_proof_run` | Not a live model |

Do not invent soak rows. Fill a row only after a real recorded run.

## Related

- [proof-run.md](proof-run.md) for the CI control-plane proof
- [examples.md](examples.md) for status / finding shapes
