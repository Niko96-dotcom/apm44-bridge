# Ultimate De-Slop Role Profiles

These role profiles are portable guidance for harnesses without Codex-style TOML agents.
The deterministic harness still owns schema validation, JSON extraction, timeouts,
state transitions, snapshots, and checks. Adapters should only select the right role
and run the prompt.

- `deslop_reviewer`: read-only whole-codebase structural review.
- `deslop_arbiter`: read-only dedupe, thresholding, rejection, prioritization, and stop advice.
- `deslop_fixer`: workspace-write repair for exactly one accepted finding.
- `deslop_verifier`: read-only independent verification of one fix.
- `deslop_scribe`: `.deslop` summaries and state only; never product files.
