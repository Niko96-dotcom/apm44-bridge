# Contributing

Thanks for helping make Ultimate De-Slop safer and more useful.

## Development Setup

```sh
git clone https://github.com/Niko96-dotcom/ultimate-de-slop.git
cd ultimate-de-slop
python3 -m unittest discover -s tests -v
```

No external service credentials are required for the local harness tests.

## Pull Request Checklist

| Area | Expected proof |
| --- | --- |
| Harness behavior | Add or update `tests/` coverage when the control plane changes. |
| Shell scripts | Run `bash -n scripts/*.sh scripts/install/*.sh`. |
| Python scripts | Run `python3 -m compileall scripts tests`. |
| Docs | Keep README tables, `references/`, and the landing page consistent. |
| Safety | Avoid broad fixer scope, hidden writes, or unbounded agent behavior. |

## Design Principles

- Keep the deterministic harness in charge of state, scoring, checks, snapshots, and lifecycle transitions.
- Keep adapters thin; they should not own finding state or validation logic.
- Keep fixers narrow; one accepted finding per run is the core safety property.
- Prefer explicit blocked or `needs_human` states over pretending a partial agent run succeeded.

## Reporting Bugs

Open an issue with:

- operating system
- selected harness and CLI version
- command run
- relevant `.deslop/runs/<run>/runner.json` fields, with secrets removed
- expected behavior and actual behavior
