#!/usr/bin/env python3
"""Record a bounded-loop outcome into .deslop/state.json."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


STOP_REASONS = {
    "stop_file",
    "no_eligible_findings",
    "max_iterations_reached",
    "finalize_halt",
}


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def fail(message: str) -> None:
    print(f"deslop-record-outcome: error: {message}", file=sys.stderr)
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


def parse_id_list(raw: str | None) -> set[str]:
    if raw is None or not raw.strip():
        return set()
    return {part.strip() for part in raw.split(",") if part.strip()}


def main() -> int:
    parser = argparse.ArgumentParser(description="Record ultimate-de-slop loop outcome.")
    parser.add_argument("--stop-reason", required=True, choices=sorted(STOP_REASONS))
    parser.add_argument("--max-iterations", type=int, required=True)
    parser.add_argument("--priority", required=True)
    parser.add_argument("--iterations-completed", type=int, required=True)
    parser.add_argument("--halt-finding-id")
    parser.add_argument("--halt-status")
    parser.add_argument(
        "--baseline-verified-ids",
        default="",
        help="comma-separated finding IDs already verified before this loop",
    )
    args = parser.parse_args()

    if args.max_iterations < 0 or args.iterations_completed < 0:
        fail("iteration counts must be non-negative")

    root = repo_root()
    state_path = root / ".deslop" / "state.json"
    state = load_json(state_path, None)
    if not isinstance(state, dict):
        fail(f"missing or invalid state at {state_path}; run deslop-init.sh first")

    findings = read_findings(root / ".deslop" / "findings.jsonl")
    baseline = parse_id_list(args.baseline_verified_ids)
    verified_ids = sorted(
        str(item.get("id"))
        for item in findings
        if item.get("status") == "verified" and str(item.get("id")) not in baseline
    )

    timestamp = now()
    outcome = {
        "at": timestamp,
        "halt_finding_id": args.halt_finding_id,
        "halt_status": args.halt_status,
        "iterations_completed": args.iterations_completed,
        "max_iterations": args.max_iterations,
        "priority": args.priority,
        "stop_reason": args.stop_reason,
        "verified_ids": verified_ids,
    }
    state["updated_at"] = timestamp
    state["loop_outcome"] = outcome
    stop = state.get("stop") if isinstance(state.get("stop"), dict) else {}
    stop_file = root / ".deslop" / "stop"
    state["stop"] = {
        "path": stop.get("path", ".deslop/stop"),
        "reason": args.stop_reason,
        "requested": stop_file.exists() or args.stop_reason == "stop_file",
    }
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    print(f"Recorded loop outcome: {args.stop_reason}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
