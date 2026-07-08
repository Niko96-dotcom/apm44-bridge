#!/usr/bin/env python3
"""Compute a simple ultimate-de-slop score."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any


NON_OPEN = {"verified", "rejected", "false_positive"}


def fail(message: str) -> None:
    print(f"deslop-score: error: {message}", file=sys.stderr)
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


def load_json(path: Path, fallback: Any) -> Any:
    if not path.exists():
        return fallback
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def read_findings(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    findings: list[dict[str, Any]] = []
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


def compute(root: Path) -> dict[str, Any]:
    findings = read_findings(root / ".deslop" / "findings.jsonl")
    inventory = load_json(root / ".deslop" / "inventory.json", {})
    open_counts = Counter(
        str(item.get("severity", "unknown")).upper()
        for item in findings
        if str(item.get("status", "")) not in NON_OPEN
    )
    over_1000 = len(inventory.get("files_over_1000_lines", []) or [])
    over_500 = len(inventory.get("files_over_500_lines", []) or [])
    penalty = (
        25 * open_counts.get("P0", 0)
        + 10 * open_counts.get("P1", 0)
        + 3 * open_counts.get("P2", 0)
        + 2 * over_1000
        + min(25, over_500)
    )
    score = max(0, 100 - penalty)
    return {
        "score": score,
        "penalty": penalty,
        "open_findings": dict(sorted(open_counts.items())),
        "files_over_1000_lines": over_1000,
        "files_over_500_lines": over_500,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Compute the ultimate-de-slop score.")
    parser.add_argument("--json", action="store_true", help="print machine-readable score")
    args = parser.parse_args()
    result = compute(repo_root())
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(f"Score: {result['score']}")
        print(f"Open findings: {result['open_findings']}")
        print(f"Files over 1000 lines: {result['files_over_1000_lines']}")
        print(f"Files over 500 lines: {result['files_over_500_lines']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
