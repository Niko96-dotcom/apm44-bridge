#!/usr/bin/env python3
"""Build a deterministic repository inventory for ultimate-de-slop."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any


DEFAULT_IGNORED = [
    "node_modules",
    ".git",
    "dist",
    "build",
    "coverage",
    "vendor",
    ".next",
    ".turbo",
    ".venv",
    "__pycache__",
]

SOURCE_EXTENSIONS = {
    ".c",
    ".cc",
    ".cpp",
    ".cs",
    ".css",
    ".go",
    ".h",
    ".hpp",
    ".html",
    ".java",
    ".js",
    ".jsx",
    ".kt",
    ".m",
    ".mm",
    ".php",
    ".py",
    ".rb",
    ".rs",
    ".sh",
    ".swift",
    ".ts",
    ".tsx",
    ".vue",
}


@dataclass(frozen=True)
class FileInfo:
    path: str
    bytes: int
    lines: int
    extension: str
    todo_count: int
    fixme_count: int


def fail(message: str) -> None:
    print(f"deslop-inventory: error: {message}", file=sys.stderr)
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


def load_config(root: Path) -> dict[str, Any]:
    path = root / ".deslop" / "config.json"
    if not path.exists():
        return {"ignored_paths": DEFAULT_IGNORED}
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")
    ignored = data.get("ignored_paths", DEFAULT_IGNORED)
    if not isinstance(ignored, list):
        ignored = DEFAULT_IGNORED
    data["ignored_paths"] = ignored
    return data


def is_ignored(rel: Path, ignored: list[str]) -> bool:
    rel_s = rel.as_posix()
    if rel.parts and rel.parts[0] == ".deslop":
        return True
    parts = set(rel.parts)
    for item in ignored:
        clean = item.strip().strip("/")
        if not clean:
            continue
        if clean in parts:
            return True
        if rel_s == clean or rel_s.startswith(clean + "/"):
            return True
    return False


def is_binary_or_too_large(path: Path, size: int) -> bool:
    if size > 2_000_000:
        return True
    try:
        chunk = path.read_bytes()[:8192]
    except OSError:
        return True
    return b"\0" in chunk


def scan_file(root: Path, path: Path) -> FileInfo | None:
    rel = path.relative_to(root).as_posix()
    try:
        size = path.stat().st_size
    except OSError:
        return None
    if is_binary_or_too_large(path, size):
        return None
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None
    return FileInfo(
        path=rel,
        bytes=size,
        lines=0 if text == "" else text.count("\n") + (0 if text.endswith("\n") else 1),
        extension=path.suffix.lower(),
        todo_count=len(re.findall(r"\bTODO\b", text, flags=re.IGNORECASE)),
        fixme_count=len(re.findall(r"\bFIXME\b", text, flags=re.IGNORECASE)),
    )


def iter_files(root: Path, ignored: list[str], max_files: int) -> tuple[list[Path], int]:
    result: list[Path] = []
    skipped = 0
    for dirpath, dirnames, filenames in os.walk(root):
        current = Path(dirpath)
        rel_dir = current.relative_to(root) if current != root else Path(".")
        kept_dirs = []
        for dirname in sorted(dirnames):
            rel = (rel_dir / dirname) if rel_dir != Path(".") else Path(dirname)
            if is_ignored(rel, ignored):
                skipped += 1
                continue
            kept_dirs.append(dirname)
        dirnames[:] = kept_dirs
        for filename in sorted(filenames):
            rel = (rel_dir / filename) if rel_dir != Path(".") else Path(filename)
            if is_ignored(rel, ignored):
                skipped += 1
                continue
            result.append(root / rel)
            if len(result) >= max_files:
                return result, skipped
    return result, skipped


def detect_package_scripts(root: Path, files: list[FileInfo]) -> list[dict[str, str]]:
    commands: list[dict[str, str]] = []
    seen: set[str] = set()

    def add(name: str, command: str, source: str) -> None:
        if command in seen:
            return
        seen.add(command)
        commands.append({"name": name, "command": command, "source": source})

    file_paths = {info.path for info in files}
    for info in files:
        rel = Path(info.path)
        if rel.name == "package.json":
            path = root / rel
            try:
                data = json.loads(path.read_text())
            except (json.JSONDecodeError, OSError):
                continue
            scripts = data.get("scripts", {})
            if not isinstance(scripts, dict):
                continue
            prefix: list[str] = []
            if rel.parent != Path("."):
                prefix = ["--prefix", rel.parent.as_posix()]
            for script in ("test", "lint", "typecheck", "build"):
                if script in scripts:
                    command = " ".join(["npm", *map(shlex.quote, prefix), "run", shlex.quote(script)])
                    add(f"npm {script}", command, info.path)
    if any(path in file_paths for path in ("pytest.ini", "pyproject.toml", "setup.cfg", "tox.ini")):
        add("pytest", "python3 -m pytest", "python")
    python_files = sorted(info.path for info in files if info.extension == ".py")
    if python_files:
        quoted = " ".join(shlex.quote(path) for path in python_files[:50])
        add("py_compile", f"python3 -m py_compile {quoted}", "python")
    if "go.mod" in file_paths:
        add("go test", "go test ./...", "go.mod")
    if "Cargo.toml" in file_paths:
        add("cargo test", "cargo test", "Cargo.toml")
    for make_name in ("Makefile", "makefile"):
        if make_name not in file_paths:
            continue
        try:
            text = (root / make_name).read_text(errors="ignore")
        except OSError:
            continue
        targets = set(re.findall(r"^([A-Za-z0-9_.-]+):", text, flags=re.MULTILINE))
        for target in ("test", "lint", "typecheck", "check", "build"):
            if target in targets:
                add(f"make {target}", f"make {target}", make_name)
    return commands


def build_inventory(root: Path, max_files: int) -> dict[str, Any]:
    config = load_config(root)
    paths, ignored_count = iter_files(root, config.get("ignored_paths", DEFAULT_IGNORED), max_files)
    scanned: list[FileInfo] = []
    skipped_binary_or_large = 0
    for path in paths:
        if not path.is_file():
            continue
        info = scan_file(root, path)
        if info is None:
            skipped_binary_or_large += 1
            continue
        scanned.append(info)

    source_files = [info for info in scanned if info.extension in SOURCE_EXTENSIONS]
    largest = sorted(scanned, key=lambda item: (-item.bytes, item.path))[:20]
    over_500 = sorted((f for f in scanned if f.lines > 500), key=lambda item: (-item.lines, item.path))
    over_1000 = [f for f in over_500 if f.lines > 1000]
    todo_files = [f for f in scanned if f.todo_count or f.fixme_count]

    source_dirs: Counter[str] = Counter()
    test_dirs: Counter[str] = Counter()
    partition_stats: dict[str, dict[str, Any]] = defaultdict(
        lambda: {"file_count": 0, "source_lines": 0, "large_files": 0, "todo_fixme": 0}
    )
    for info in source_files:
        parts = Path(info.path).parts
        top = parts[0] if len(parts) > 1 else "."
        source_dirs[top] += 1
        stats = partition_stats[top]
        stats["file_count"] += 1
        stats["source_lines"] += info.lines
        stats["large_files"] += 1 if info.lines > 500 else 0
        stats["todo_fixme"] += info.todo_count + info.fixme_count
        lowered = info.path.lower()
        if any(part in {"test", "tests", "__tests__", "spec", "specs"} for part in parts) or re.search(
            r"(_test|\.test|\.spec)\.", lowered
        ):
            test_dirs[top] += 1

    tooling_files = sorted(
        info.path
        for info in scanned
        if Path(info.path).name
        in {
            "package.json",
            "pyproject.toml",
            "pytest.ini",
            "go.mod",
            "Cargo.toml",
            "Makefile",
            "makefile",
            "pnpm-lock.yaml",
            "package-lock.json",
            "yarn.lock",
        }
    )

    partitions = [
        {"path": key, **value}
        for key, value in sorted(
            partition_stats.items(),
            key=lambda item: (-item[1]["source_lines"], item[0]),
        )
    ][:30]

    inventory = {
        "version": 1,
        "repo_root": str(root),
        "scanned_file_count": len(scanned),
        "candidate_file_count": len(paths),
        "ignored_path_count": ignored_count,
        "skipped_binary_or_large_count": skipped_binary_or_large,
        "largest_files": [asdict(item) for item in largest],
        "files_over_500_lines": [asdict(item) for item in over_500[:50]],
        "files_over_1000_lines": [asdict(item) for item in over_1000[:50]],
        "todo_fixme_counts": {
            "total_todo": sum(item.todo_count for item in todo_files),
            "total_fixme": sum(item.fixme_count for item in todo_files),
            "files": [asdict(item) for item in sorted(todo_files, key=lambda item: (item.path))[:50]],
        },
        "likely_source_directories": [
            {"path": path, "source_file_count": count} for path, count in source_dirs.most_common(30)
        ],
        "test_directories": [
            {"path": path, "test_file_count": count} for path, count in test_dirs.most_common(30)
        ],
        "detected_tooling_files": tooling_files,
        "detected_commands": detect_package_scripts(root, scanned),
        "risk_partitions": partitions,
    }
    return inventory


def render_index(inventory: dict[str, Any]) -> str:
    lines = [
        "# Ultimate De-Slop Index",
        "",
        f"Repo root: `{inventory['repo_root']}`",
        f"Scanned files: {inventory['scanned_file_count']}",
        f"Skipped binary or giant files: {inventory['skipped_binary_or_large_count']}",
        "",
        "## Detected Commands",
        "",
    ]
    commands = inventory.get("detected_commands", [])
    if commands:
        for command in commands:
            lines.append(f"- `{command['command']}` ({command['source']})")
    else:
        lines.append("- No deterministic project commands detected.")
    lines.extend(["", "## Largest Files", ""])
    for item in inventory.get("largest_files", [])[:10]:
        lines.append(f"- `{item['path']}`: {item['lines']} lines, {item['bytes']} bytes")
    lines.extend(["", "## Files Over 500 Lines", ""])
    over_500 = inventory.get("files_over_500_lines", [])
    if over_500:
        for item in over_500[:20]:
            lines.append(f"- `{item['path']}`: {item['lines']} lines")
    else:
        lines.append("- None detected.")
    lines.extend(["", "## Risk Partitions", ""])
    partitions = inventory.get("risk_partitions", [])
    if partitions:
        for item in partitions[:20]:
            lines.append(
                f"- `{item['path']}`: {item['source_lines']} source lines, "
                f"{item['file_count']} files, {item['large_files']} large files, "
                f"{item['todo_fixme']} TODO/FIXME"
            )
    else:
        lines.append("- No source partitions detected.")
    lines.extend(
        [
            "",
            "## Suggested Commands",
            "",
            "- `scripts/deslop-loop.sh --max-iterations 5 --priority P0,P1`",
            "- `scripts/deslop-review.sh`",
            "- `scripts/deslop-status.py`",
            "- `scripts/deslop-next.py`",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a deterministic ultimate-de-slop repo inventory.")
    parser.add_argument("--json", action="store_true", help="print inventory JSON to stdout")
    parser.add_argument("--write", action="store_true", help="write .deslop/inventory.json and .deslop/index.md")
    parser.add_argument("--max-files", type=int, default=20000, help="maximum candidate files to scan")
    args = parser.parse_args()

    root = repo_root()
    inventory = build_inventory(root, args.max_files)

    if args.write:
        deslop = root / ".deslop"
        deslop.mkdir(exist_ok=True)
        (deslop / "inventory.json").write_text(json.dumps(inventory, indent=2, sort_keys=True) + "\n")
        (deslop / "index.md").write_text(render_index(inventory))
    if args.json or not args.write:
        print(json.dumps(inventory, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
