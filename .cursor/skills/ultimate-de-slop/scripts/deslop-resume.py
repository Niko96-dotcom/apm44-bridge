#!/usr/bin/env python3
"""Resume a needs_human or blocked finding into a resolvable state."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ALLOWED_SOURCES = {"needs_human", "blocked"}
ALLOWED_TARGETS = {"accepted", "rejected", "false_positive", "verified"}
NON_OPEN = {"verified", "rejected", "false_positive"}


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def fail(message: str) -> None:
    print(f"deslop-resume: error: {message}", file=sys.stderr)
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


def write_findings(path: Path, findings: list[dict[str, Any]]) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text("".join(json.dumps(item, sort_keys=True) + "\n" for item in findings))
    tmp.replace(path)


def summarize(findings: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "total": len(findings),
        "by_status": dict(sorted(Counter(str(item.get("status", "unknown")) for item in findings).items())),
        "open_by_severity": dict(
            sorted(
                Counter(
                    str(item.get("severity", "unknown")).upper()
                    for item in findings
                    if str(item.get("status", "")) not in NON_OPEN
                ).items()
            )
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Resume a needs_human or blocked finding.")
    parser.add_argument("finding_id", help="finding ID such as DSL-000001")
    parser.add_argument(
        "--as",
        dest="target_status",
        required=True,
        choices=sorted(ALLOWED_TARGETS),
        help="new status for the finding",
    )
    parser.add_argument("--reason", default="", help="human reason for the resume decision")
    args = parser.parse_args()

    root = repo_root()
    findings_path = root / ".deslop" / "findings.jsonl"
    findings = read_findings(findings_path)
    finding = next((item for item in findings if item.get("id") == args.finding_id), None)
    if not finding:
        fail(f"finding not found: {args.finding_id}")

    current = str(finding.get("status", ""))
    if current not in ALLOWED_SOURCES:
        fail(
            f"cannot resume finding in status {current!r}; "
            f"allowed sources: {', '.join(sorted(ALLOWED_SOURCES))}"
        )

    timestamp = now()
    previous = current
    finding["status"] = args.target_status
    finding["updated_at"] = timestamp
    finding["resume"] = {
        "at": timestamp,
        "from_status": previous,
        "reason": args.reason or None,
        "to_status": args.target_status,
    }
    if args.target_status == "verified":
        finding["verified_at"] = timestamp
    if args.target_status == "accepted":
        finding.pop("block_reason", None)

    write_findings(findings_path, findings)

    config = load_json(root / ".deslop" / "config.json", {})
    state_path = root / ".deslop" / "state.json"
    state = load_json(state_path, {})
    if not isinstance(state, dict):
        state = {}
    state["updated_at"] = timestamp
    state["repo_root"] = str(root)
    state["config"] = config if isinstance(config, dict) else {}
    state["counters"] = summarize(findings)
    state["open_findings_summary"] = state["counters"].get("open_by_severity", {})
    state["last_run"] = {
        "kind": "resume",
        "finding_id": args.finding_id,
        "at": timestamp,
        "from_status": previous,
        "to_status": args.target_status,
    }
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")

    print(f"Finding {args.finding_id}: {previous} -> {args.target_status}")
    if args.reason:
        print(f"Reason: {args.reason}")
    if args.target_status == "accepted":
        print(f"Next: scripts/deslop-fix.sh {args.finding_id}")
    else:
        print("Next: scripts/deslop-status.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
