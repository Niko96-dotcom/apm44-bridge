# Ultimate De-Slop on Cursor Cloud (apm44-bridge)

This repo vendors [Ultimate De-Slop](https://github.com/Niko96-dotcom/ultimate-de-slop) as a Cursor project skill and adds a **cloud bridge** so Cloud Agents can run the bounded review → fix → check → verify loop without `CURSOR_API_KEY`.

## Two different "deslop" skills

| Skill | What it is | When to use |
| --- | --- | --- |
| `cursor-team-kit` `/deslop` | Diff cleanup: strip AI slop from the current branch | After a feature PR, before merge |
| **Ultimate De-Slop** (this doc) | Whole-repo bounded quality loop with arbitration + verification | Repo-wide maintainability / correctness cleanup |

## Why a cloud bridge?

Ultimate De-Slop's `DESLOP_HARNESS=cursor` adapter shells out to `cursor-agent --print`. Cloud VMs can install that CLI (`curl https://cursor.com/install | bash`), but they typically have **no login / API key**, so review/fix/verify exit with auth errors.

The bridge puts `scripts/deslop-cloud/cursor-agent` first on `PATH`. That shim:

1. Records the harness prompt under `.deslop/cloud/`
2. Serves JSON from `.deslop/cloud/response.json` when present
3. Otherwise exits `42` so the parent Cloud Agent can fill the child role

Deterministic stages (`init`, `inventory`, `status`, `next`, `run-checks`, arbitration, finalize) need no child agent and already work in Cloud.

## Install / refresh the skill

Already present at `.cursor/skills/ultimate-de-slop`. To refresh from upstream:

```sh
git clone --depth 1 https://github.com/Niko96-dotcom/ultimate-de-slop.git /tmp/ultimate-de-slop
/tmp/ultimate-de-slop/scripts/install/install-cursor.sh --scope local --project-dir "$PWD"
# Optional: drop landing-page assets to keep the tree small
rm -rf .cursor/skills/ultimate-de-slop/docs/assets
```

`.deslop/` is gitignored (harness state only).

## Cloud Agent playbook

```sh
# 0) Doctor + inventory (deterministic)
scripts/deslop-cloud/run-stage.sh doctor
scripts/deslop-cloud/run-stage.sh status

# 1) Review wave
scripts/deslop-cloud/run-stage.sh review
# exit 42 → parent agent reads .deslop/cloud/prompt.txt + .deslop/index.md,
# writes schema-valid review JSON to .deslop/cloud/response.json, then:
scripts/deslop-cloud/run-stage.sh review

# 2) Fix one accepted finding
id="$(scripts/deslop-cloud/run-stage.sh next)"
scripts/deslop-cloud/run-stage.sh fix "$id"
# exit 42 → apply the one-finding fix in the workspace, write fix JSON, re-run

# 3) Checks + verify
scripts/deslop-cloud/run-stage.sh checks "$id"
scripts/deslop-cloud/run-stage.sh verify "$id"
# exit 42 → write verify JSON, re-run
```

Review JSON must match `.cursor/skills/ultimate-de-slop/references/review.schema.json`.
Fix JSON must match `fix.schema.json`. Verify JSON must match `verify.schema.json`.

## Authenticated alternative (local / CI with key)

If `CURSOR_API_KEY` is available:

```sh
export PATH="$HOME/.local/bin:$PATH"
export DESLOP_HARNESS=cursor
export CURSOR_API_KEY=...
.cursor/skills/ultimate-de-slop/scripts/deslop-loop.sh --max-iterations 5 --priority P0,P1
```

Do **not** put the cloud shim ahead of PATH in that mode.

## Safety defaults (unchanged)

- Review / arbitration / verify are read-only roles
- Fixer handles exactly one accepted finding
- P3 / style nits are rejected by default
- Commits and auto-revert are opt-in
- Stop with `touch .deslop/stop`

## Completing a fix after exit 42

`deslop-fix.sh` snapshots the tree *before* the child agent runs. If the parent
Cloud Agent edits the tree first and then re-invokes `run-stage.sh fix`, the
harness treats the edit as pre-existing and blocks the finding.

After applying the fix and writing `.deslop/cloud/response.json`, finish the
awaiting run with:

```sh
scripts/deslop-cloud/complete-fix.sh DSL-000001
```

