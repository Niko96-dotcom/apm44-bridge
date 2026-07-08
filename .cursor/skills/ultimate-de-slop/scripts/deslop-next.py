#!/usr/bin/env python3
"""Choose the next accepted ultimate-de-slop finding."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    print(f"deslop-next: error: {message}", file=sys.stderr)
    raise SystemExit(1)


def repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=Path.cwd(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        fail("could not resolve git root; run from inside a git repository")
    return Path(result.stdout.strip()).resolve()


def read_findings(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    findings = []
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            fail(f"invalid JSONL in {path}:{number}: {exc}")
        if isinstance(item, dict):
            findings.append(item)
    return findings


def choose(findings: list[dict[str, Any]], priorities: list[str]) -> dict[str, Any] | None:
    effort_rank = {"small": 0, "medium": 1, "large": 2}
    eligible = [
        item
        for item in findings
        if item.get("status") == "accepted" and str(item.get("severity", "")).upper() in priorities
    ]
    if not eligible:
        return None
    eligible.sort(
        key=lambda item: (
            priorities.index(str(item.get("severity", "")).upper()),
            -float(item.get("confidence", 0) or 0),
            effort_rank.get(str(item.get("estimated_effort", "")).lower(), 9),
            str(item.get("id")),
        )
    )
    return eligible[0]


def main() -> int:
    parser = argparse.ArgumentParser(description="Print the next accepted ultimate-de-slop finding ID.")
    parser.add_argument("--priority", default="P0,P1,P2", help="comma-separated severity priority list")
    parser.add_argument("--json", action="store_true", help="print full next finding as JSON")
    args = parser.parse_args()

    priorities = [part.strip().upper() for part in args.priority.split(",") if part.strip()]
    if not priorities:
        fail("--priority must include at least one severity")
    root = repo_root()
    finding = choose(read_findings(root / ".deslop" / "findings.jsonl"), priorities)
    if args.json:
        print(json.dumps({"next": finding}, indent=2, sort_keys=True))
    else:
        print(finding.get("id") if finding else "NONE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
