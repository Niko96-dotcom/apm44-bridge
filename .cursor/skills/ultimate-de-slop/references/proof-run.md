# Deterministic Proof Run

This repository proves the Ultimate De-Slop control plane without calling a live model.

## What it proves

A fake Codex CLI on `PATH` drives one bounded loop against a tiny fixture repo:

1. Review emits one high-confidence P1 finding with concrete evidence.
2. Arbitration accepts it.
3. Fixer edits the duplicated validation helper and reports a bounded fix.
4. Deterministic checks pass (`python3 -m py_compile`).
5. Verifier returns `PASS` with non-empty evidence.
6. Finalize marks the finding `verified`.
7. The next review wave finds nothing eligible.
8. `deslop-status` / `state.loop_outcome` report `stop_reason=no_eligible_findings` and the verified finding id.

## How to run

```sh
python3 -m unittest tests.test_harness.HarnessTests.test_deterministic_proof_run -v
```

Or the full control-plane suite:

```sh
make ci
```

## Why this is the right proof shape

Live LLM runs are useful demos, but they are non-deterministic and expensive for CI. The harness claim is that the outer loop is auditable and restartable even when agent output is imperfect. A kind-driven fake CLI exercises that claim: prompts, JSON extraction, arbitration, snapshots, checks, verification gates, finalize, and loop outcome persistence all run for real.

## Live soaks

For real harness/model soaks, use the template in [soak-runs.md](soak-runs.md).
