# Architecture

`ultimate-de-slop` is an outer deterministic harness wrapped around bounded child-agent calls.

The deterministic layer owns repo-root discovery, inventory, state files, findings, IDs, score calculation, check execution, child-agent execution, JSON extraction, and loop stop conditions. This keeps the workflow auditable and restartable even when agent output is imperfect.

The agent layer is intentionally narrow:

- Reviewer: read-only whole-codebase structural review.
- Arbiter: read-only dedupe, thresholding, rejection, prioritization, and stop-policy advice.
- Fixer: workspace-write, one accepted finding only.
- Verifier: read-only independent judgment of the patch against the original finding and checks.
- Scribe: `.deslop` state and summary maintenance only.

The loop flow is:

1. Initialize `.deslop`.
2. Inventory the repo.
3. Check for queued accepted findings.
4. If an accepted finding exists, fix it before starting another review.
5. If no accepted finding exists, review by partitions in read-only mode.
6. Arbitrate and persist accepted findings.
7. Fix exactly one accepted finding.
8. Run deterministic checks.
9. Verify independently in read-only mode.
10. Finalize state and optionally commit.
11. Repeat only until an explicit stop policy triggers.

The harness should optimize for high-confidence structural improvements. It should not become a style churn machine or a rewrite launcher.

Child calls go through `scripts/deslop-agent-runner.py`; `scripts/deslop-codex-runner.py` is a compatibility shim. The runner provides the execution contract the shell scripts depend on: prompt via stdin, explicit working root, harness selection through `DESLOP_HARNESS`, final-message capture or equivalent, raw output capture, wall-clock timeout, idle timeout, and a machine-readable `runner.json`. Codex uses native schema and last-message flags. Other adapters provide best-effort JSON mode and rely on the deterministic extraction fallback. Runner output schemas must stay compatible with strict structured-output validation: object schemas close over `additionalProperties: false`, and every declared property is listed in `required`.

Adapters must stay thin. They construct a CLI command from root/cwd, prompt file, raw output path, last message path, runner JSON path, schema path, sandbox/permission mode, kind/role, optional model, and optional extra directories. They must not own finding lifecycle, JSON extraction, timeout policy, state transitions, snapshots, or checks.

Fix attempts record git status and diff snapshots before and after the fixer runs. The verifier receives both the full current diff and a per-finding patch-of-patches, so a no-commit loop can continue across earlier verified uncommitted fixes without making the verifier judge unrelated accumulated changes as part of the current finding.

If a fixer fails or times out after changing the worktree, the finding is marked `needs_human`; stale dirty state is not counted as a successful fix.
