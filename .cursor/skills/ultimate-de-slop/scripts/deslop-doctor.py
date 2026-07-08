#!/usr/bin/env python3
"""Diagnose Ultimate De-Slop harness readiness before a loop."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


HARNESS_CLI = {
    "claude": "claude",
    "codex": "codex",
    "commandcode": "commandcode",
    "cursor": "cursor-agent",
    "hermes": "hermes",
    "opencode": "opencode",
    "openclaw": "openclaw",
    "pi": "pi",
}

AUTH_ENV = {
    "cursor": ["CURSOR_API_KEY", "CURSOR_AUTH_TOKEN"],
}


def fail(message: str) -> None:
    print(f"deslop-doctor: error: {message}", file=sys.stderr)
    raise SystemExit(1)


def repo_root_optional() -> Path | None:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=Path.cwd(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError:
        return None
    if result.returncode != 0:
        return None
    return Path(result.stdout.strip()).resolve()


def selected_model(harness: str) -> str | None:
    names = [
        "DESLOP_MODEL",
        f"DESLOP_{harness.upper().replace('-', '_')}_MODEL",
    ]
    if harness == "codex":
        names.append("DESLOP_CODEX_MODEL")
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return None


def check_item(ok: bool, code: str, message: str, *, level: str | None = None) -> dict[str, Any]:
    resolved_level = level or ("ok" if ok else "error")
    return {"ok": ok, "code": code, "level": resolved_level, "message": message}


def build_report(harness: str | None = None) -> dict[str, Any]:
    harness_name = (harness or os.environ.get("DESLOP_HARNESS") or "codex").strip().lower()
    checks: list[dict[str, Any]] = []
    if harness_name not in HARNESS_CLI:
        checks.append(
            check_item(
                False,
                "unknown_harness",
                f"Unsupported DESLOP_HARNESS={harness_name!r}; expected one of: {', '.join(sorted(HARNESS_CLI))}",
            )
        )
        return {
            "harness": harness_name,
            "model": selected_model(harness_name),
            "ready": False,
            "checks": checks,
        }

    cli = HARNESS_CLI[harness_name]
    cli_path = shutil.which(cli)
    checks.append(
        check_item(
            cli_path is not None,
            "cli_on_path",
            f"{cli} found at {cli_path}" if cli_path else f"{cli} not found on PATH for DESLOP_HARNESS={harness_name}",
        )
    )

    if harness_name == "openclaw":
        checks.append(
            check_item(
                False,
                "openclaw_unsupported",
                "OpenClaw adapter intentionally fails until its noninteractive schema-output CLI contract is confirmed.",
            )
        )

    auth_names = AUTH_ENV.get(harness_name, [])
    if auth_names:
        present = [name for name in auth_names if os.environ.get(name)]
        if present:
            checks.append(
                check_item(
                    True,
                    "auth_env",
                    f"Auth env present: {', '.join(present)}",
                )
            )
        elif (
            harness_name == "cursor"
            and cli_path is not None
            and Path(cli_path).resolve().as_posix().endswith("/scripts/deslop-cloud/cursor-agent")
        ):
            checks.append(
                check_item(
                    True,
                    "auth_env",
                    "Cursor Cloud shim detected at scripts/deslop-cloud/cursor-agent; parent agent supplies role JSON via .deslop/cloud/response.json.",
                )
            )
        else:
            checks.append(
                check_item(
                    False,
                    "auth_env",
                    f"Missing auth for {harness_name}. Set one of {', '.join(auth_names)} or run `{cli} login`.",
                )
            )

    model = selected_model(harness_name)
    checks.append(
        check_item(
            True,
            "model",
            f"Model: {model}" if model else "Model: harness default (set DESLOP_MODEL to pin one)",
            level="ok",
        )
    )

    root = repo_root_optional()
    if root is None:
        checks.append(
            check_item(
                False,
                "git_repo",
                "Not inside a git repository; deslop commands require a git root.",
                level="warning",
            )
        )
    else:
        deslop = root / ".deslop"
        required = ["config.json", "state.json", "findings.jsonl", "inventory.json", "index.md"]
        missing = [name for name in required if not (deslop / name).exists()]
        if missing:
            checks.append(
                check_item(
                    False,
                    "deslop_init",
                    f".deslop is incomplete (missing {', '.join(missing)}). Run scripts/deslop-init.sh.",
                    level="warning",
                )
            )
        else:
            checks.append(
                check_item(
                    True,
                    "deslop_init",
                    f".deslop initialized under {deslop}",
                )
            )

    ready = all(item["ok"] or item["level"] == "warning" for item in checks) and all(
        item["level"] != "error" for item in checks
    )
    # ready means no error-level failures
    ready = not any(item["level"] == "error" for item in checks)
    return {
        "checks": checks,
        "harness": harness_name,
        "model": model,
        "ready": ready,
        "repo_root": str(root) if root else None,
        "suggested_commands": suggested(ready, harness_name),
    }


def suggested(ready: bool, harness: str) -> list[str]:
    if not ready:
        return [
            "Fix the error checks above, then re-run scripts/deslop-doctor.py",
            f"export DESLOP_HARNESS={harness}",
            "export DESLOP_MODEL=<model-id>   # optional",
        ]
    return [
        "scripts/deslop-init.sh",
        "scripts/deslop-status.py",
        "scripts/deslop-loop.sh --max-iterations 5 --priority P0,P1",
    ]


def print_human(report: dict[str, Any]) -> None:
    print("Ultimate De-Slop Doctor")
    print(f"Harness: {report['harness']}")
    print(f"Model: {report.get('model') or 'default'}")
    print(f"Ready: {'yes' if report['ready'] else 'no'}")
    if report.get("repo_root"):
        print(f"Repo: {report['repo_root']}")
    print("Checks:")
    for item in report["checks"]:
        mark = "OK" if item["ok"] else item["level"].upper()
        print(f"  [{mark}] {item['code']}: {item['message']}")
    print("Suggested commands:")
    for command in report["suggested_commands"]:
        print(f"  {command}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Diagnose Ultimate De-Slop harness readiness.")
    parser.add_argument("--harness", help="override DESLOP_HARNESS")
    parser.add_argument("--json", action="store_true", help="print machine-readable report")
    args = parser.parse_args()
    report = build_report(args.harness)
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print_human(report)
    return 0 if report["ready"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
