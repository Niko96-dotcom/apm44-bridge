# Ultimate De-Slop

[![CI](https://github.com/Niko96-dotcom/ultimate-de-slop/actions/workflows/ci.yml/badge.svg)](https://github.com/Niko96-dotcom/ultimate-de-slop/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-111827.svg)](LICENSE)
[![GitHub Pages](https://img.shields.io/badge/landing-page-0f766e.svg)](https://niko96-dotcom.github.io/ultimate-de-slop/)
[![Built for agent CLIs](https://img.shields.io/badge/agent--cli-Codex%20%7C%20Claude%20%7C%20OpenCode%20%7C%20Cursor-2563eb.svg)](#adapter-matrix)

**Ultimate De-Slop is a local, auditable harness for bounded AI-agent code-quality repair loops.** It turns vague "clean this repo up" energy into a controlled pipeline: strict structural review, conservative arbitration, one-finding fixes, deterministic checks, independent verification, and explicit stop rules.

![Ultimate De-Slop workflow hero](docs/assets/ultimate-de-slop-hero.png)

## Why It Exists

Most agent cleanup sessions fail in one of two ways: they either stop at a pile of findings, or they keep editing until the diff is too broad to trust. Ultimate De-Slop sits outside the agent and keeps the loop narrow, restartable, and inspectable.

| Problem | Ultimate De-Slop response |
| --- | --- |
| Broad rewrites | Fixers receive exactly one accepted finding at a time. |
| Weak or subjective findings | A read-only arbiter rejects vague, low-confidence, or stylistic work. |
| Hidden agent output | Prompts, raw output, extracted JSON, check logs, and state are written under `.deslop/`. |
| Verification drift | A separate read-only verifier judges the patch against the original finding and checks. |
| Infinite loops | Iteration caps, attempt caps, stop files, dirty-tree checks, and verifier outcomes halt the run. |

## Quick Start

Clone and install the skill for your agent harness:

```sh
git clone https://github.com/Niko96-dotcom/ultimate-de-slop.git
cd ultimate-de-slop
scripts/install/install-codex.sh
```

Run the harness inside the repository you want to improve:

```sh
SKILL_DIR="$HOME/.codex/skills/ultimate-de-slop"
cd /path/to/your/repo
"$SKILL_DIR/scripts/deslop-init.sh"
"$SKILL_DIR/scripts/deslop-doctor.py"
"$SKILL_DIR/scripts/deslop-status.py"
"$SKILL_DIR/scripts/deslop-loop.sh" --max-iterations 5 --priority P0,P1
```

Use review-only mode when you want findings without edits:

```sh
"$SKILL_DIR/scripts/deslop-review.sh"
```

## Loop Lifecycle

| Stage | Actor | Write access | Output |
| --- | --- | --- | --- |
| Inventory | deterministic harness | `.deslop/` only | repo map, command hints, risk partitions |
| Review | reviewer agent | read-only | candidate P0/P1/P2 findings |
| Arbitration | arbiter agent + harness | read-only | accepted, rejected, merged, next finding |
| Fix | fixer agent | workspace-write | one bounded patch |
| Checks | deterministic harness | run logs only | pass/fail/blocked check records |
| Verify | verifier agent | read-only | PASS, FAIL, NEEDS_HUMAN, or FALSE_POSITIVE |
| Finalize | deterministic harness | `.deslop/` and optional git commit | updated state and next command |

## Safety Defaults

| Default | Value |
| --- | --- |
| Review, arbitration, verification | read-only |
| Fixer scope | one accepted finding |
| P3/style nit fuel | rejected by default |
| Parallel writers | disabled |
| Commits | opt-in with `--commit` |
| Auto revert | opt-in with `--auto-revert` |
| Dirty tree | blocked unless `--allow-dirty` |
| Runtime stop | `touch .deslop/stop` |

## Adapter Matrix

| Harness | Status | Invocation style |
| --- | --- | --- |
| Codex | supported default | `codex exec` with schema and last-message capture |
| Claude | supported adapter | `claude -p` with JSON/schema flags where available |
| OpenCode | supported adapter | `opencode run --format json --file <prompt>` |
| Cursor | supported adapter | `cursor-agent --print --output-format json` |
| Pi | supported adapter | `pi --print` with prompt-file instructions |
| Command Code | supported adapter | `commandcode --print` |
| Hermes | supported adapter | `hermes -z <prompt-file instruction>` |
| OpenClaw | guarded adapter | conservative actionable failure until CLI contract is confirmed |

Select a harness per run:

```sh
DESLOP_HARNESS=opencode "$SKILL_DIR/scripts/deslop-review.sh"
DESLOP_HARNESS=codex DESLOP_MODEL=gpt-5.3-codex-spark "$SKILL_DIR/scripts/deslop-loop.sh" --max-iterations 3
```

## Installation Options

Installers live under `scripts/install/` and accept `--scope global`, `--scope local`, `--project-dir PATH`, `--home PATH`, and `--dry-run`.

| Command | Installs for |
| --- | --- |
| `scripts/install/install-codex.sh` | Codex skill and Codex agent profiles |
| `scripts/install/install-claude.sh` | Claude skill directory |
| `scripts/install/install-opencode.sh` | OpenCode skill directory |
| `scripts/install/install-cursor.sh` | Cursor skill directory |
| `scripts/install/install-pi.sh` | Pi skill directory |
| `scripts/install/install-commandcode.sh` | Command Code skill directory |
| `scripts/install/install-hermes.sh` | Hermes software-development skill directory |
| `scripts/install/install-openclaw.sh` | OpenClaw skill directory |
| `scripts/install/install-all.sh` | every supported layout |

## Artifacts

| Path | Purpose |
| --- | --- |
| `.deslop/config.json` | local loop settings |
| `.deslop/inventory.json` | deterministic repository inventory |
| `.deslop/index.md` | human-readable inventory and command summary |
| `.deslop/findings.jsonl` | append-friendly finding state |
| `.deslop/state.json` | counters, stop state, loop outcome, and loop metadata |
| `scripts/deslop-doctor.py` | harness PATH/auth/model readiness check |
| `scripts/deslop-resume.py` | resolve `needs_human` / `blocked` findings |
| `.deslop/runs/` | prompts, raw output, extracted JSON, check logs |

Runtime artifacts are intentionally gitignored in this repository.

## Repository Map

| Path | Contents |
| --- | --- |
| `scripts/` | deterministic harness, loop, status, scoring, checks, agent runner |
| `scripts/install/` | multi-harness installers |
| `references/` | architecture notes, rubrics, schemas, stop policy, examples |
| `templates/` | Codex agent profiles and portable role guidance |
| `tests/` | local unittest coverage for the control plane |
| `docs/` | GitHub Pages landing page |

## Loop Outcome Summary

After a bounded loop exits, `deslop-status.py` prints why it stopped, which findings were verified in that run, what is still queued, and any `needs_human` / `false_positive` reasons. The same summary is persisted as `.deslop/state.json` → `loop_outcome`.

## Deterministic Proof

CI proves the control plane without a live model. A fake Codex CLI drives review → fix → checks → verify → finalize and asserts a clear `no_eligible_findings` stop outcome. See [references/proof-run.md](references/proof-run.md) and the live soak template in [references/soak-runs.md](references/soak-runs.md).

```sh
python3 -m unittest tests.test_harness.HarnessTests.test_deterministic_proof_run -v
```

## Development

Run the local control-plane tests:

```sh
python3 -m unittest discover -s tests -v
```

Run syntax checks:

```sh
python3 -m compileall scripts tests
bash -n scripts/*.sh scripts/install/*.sh
```

## Project Links

| Resource | Link |
| --- | --- |
| Landing page | <https://niko96-dotcom.github.io/ultimate-de-slop/> |
| Issues | <https://github.com/Niko96-dotcom/ultimate-de-slop/issues> |
| Discussions | <https://github.com/Niko96-dotcom/ultimate-de-slop/discussions> |
| Security policy | [SECURITY.md](SECURITY.md) |
| Contributing guide | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Changelog | [CHANGELOG.md](CHANGELOG.md) |

## License

MIT. See [LICENSE](LICENSE).

## Cursor Cloud consumer note (apm44-bridge)

This install is consumed by `apm44-bridge` with a PATH shim at
`scripts/deslop-cloud/cursor-agent`. When no `CURSOR_API_KEY` is available, the
parent Cloud Agent writes role JSON to `.deslop/cloud/response.json` and re-runs
`scripts/deslop-cloud/run-stage.sh`. See `docs/ultimate-de-slop-cloud.md`.

