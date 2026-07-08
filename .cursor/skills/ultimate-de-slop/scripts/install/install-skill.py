#!/usr/bin/env python3
"""Install ultimate-de-slop into harness-specific skill directories."""

from __future__ import annotations

import argparse
import filecmp
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path


SKILL_NAME = "ultimate-de-slop"
INSTALLER_VERSION = 2

LAYOUTS = {
    "agents": {
        "global": Path(".agents/skills") / SKILL_NAME,
        "local": Path(".agents/skills") / SKILL_NAME,
        "runner_harness": None,
        "label": "shared portable fallback",
    },
    "claude": {
        "global": Path(".claude/skills") / SKILL_NAME,
        "local": Path(".claude/skills") / SKILL_NAME,
        "runner_harness": "claude",
        "label": "Claude",
    },
    "codex": {
        "global": Path(".codex/skills") / SKILL_NAME,
        "local": Path(".codex/skills") / SKILL_NAME,
        "runner_harness": "codex",
        "label": "Codex",
    },
    "commandcode": {
        "global": Path(".commandcode/skills") / SKILL_NAME,
        "local": Path(".commandcode/skills") / SKILL_NAME,
        "runner_harness": "commandcode",
        "label": "Command Code",
    },
    "cursor": {
        "global": Path(".cursor/skills") / SKILL_NAME,
        "local": Path(".cursor/skills") / SKILL_NAME,
        "runner_harness": "cursor",
        "label": "Cursor",
    },
    "hermes": {
        "global": Path(".hermes/skills/software-development") / SKILL_NAME,
        "local": Path(".hermes/skills/software-development") / SKILL_NAME,
        "runner_harness": "hermes",
        "label": "Hermes",
    },
    "opencode": {
        "global": Path(".config/opencode/skills") / SKILL_NAME,
        "local": Path(".opencode/skills") / SKILL_NAME,
        "runner_harness": "opencode",
        "label": "OpenCode",
    },
    "openclaw": {
        "global": Path(".openclaw/skills") / SKILL_NAME,
        "local": Path(".openclaw/skills") / SKILL_NAME,
        "runner_harness": "openclaw",
        "label": "OpenClaw",
    },
    "pi": {
        "global": Path(".pi/skills") / SKILL_NAME,
        "local": Path(".pi/skills") / SKILL_NAME,
        "runner_harness": "pi",
        "label": "Pi",
    },
}

SKIP_DIRS = {".git", ".deslop", "__pycache__"}
SKIP_NAMES = {".DS_Store"}
MARKER = ".ultimate-de-slop-install.json"


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def skill_root() -> Path:
    return Path(__file__).resolve().parents[2]


def should_skip(path: Path) -> bool:
    if path.name in SKIP_NAMES or path.suffix == ".pyc":
        return True
    return any(part in SKIP_DIRS for part in path.parts)


def target_path(harness: str, scope: str, home: Path, project_dir: Path) -> Path:
    base = home if scope == "global" else project_dir
    return base / LAYOUTS[harness][scope]


def same_path(left: Path, right: Path) -> bool:
    try:
        return left.resolve() == right.resolve()
    except FileNotFoundError:
        return False


def read_marker(target: Path) -> dict[str, object] | None:
    marker = target / MARKER
    if not marker.exists():
        return None
    try:
        data = json.loads(marker.read_text())
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def copy_tree(source: Path, target: Path) -> None:
    target.mkdir(parents=True, exist_ok=True)
    for item in source.rglob("*"):
        rel = item.relative_to(source)
        if should_skip(rel):
            continue
        destination = target / rel
        if item.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
            continue
        if item.is_symlink():
            if destination.exists() or destination.is_symlink():
                destination.unlink()
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.symlink_to(os.readlink(item))
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() and filecmp.cmp(item, destination, shallow=False):
            continue
        shutil.copy2(item, destination)


def backup_existing(target: Path, dry_run: bool) -> Path | None:
    if not target.exists() or read_marker(target):
        return None
    backup = target.with_name(f"{target.name}.backup.{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}")
    if dry_run:
        return backup
    suffix = 1
    candidate = backup
    while candidate.exists():
        suffix += 1
        candidate = target.with_name(f"{backup.name}.{suffix}")
    shutil.copytree(target, candidate, symlinks=True)
    return candidate


def write_marker(target: Path, harness: str, scope: str, source: Path) -> None:
    payload = {
        "installer": "ultimate-de-slop",
        "installer_version": INSTALLER_VERSION,
        "harness": harness,
        "scope": scope,
        "source": str(source),
        "installed_at": now(),
    }
    (target / MARKER).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def install_codex_profiles(source: Path, scope: str, home: Path, project_dir: Path, dry_run: bool) -> list[str]:
    base = home / ".codex" if scope == "global" else project_dir / ".codex"
    template_root = source / "templates" / "codex"
    actions: list[str] = []
    agents_source = template_root / "agents"
    agents_target = base / "agents"
    if agents_source.exists():
        for item in sorted(agents_source.glob("*.toml")):
            destination = agents_target / item.name
            actions.append(f"agent profile: {destination}")
            if not dry_run:
                destination.parent.mkdir(parents=True, exist_ok=True)
                if destination.exists() and not filecmp.cmp(item, destination, shallow=False):
                    shutil.copy2(destination, destination.with_suffix(destination.suffix + f".backup.{now()}"))
                shutil.copy2(item, destination)
    config_source = template_root / "config.toml"
    config_target = base / "config.toml"
    if config_source.exists() and not config_target.exists():
        actions.append(f"codex config: {config_target}")
        if not dry_run:
            config_target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(config_source, config_target)
    return actions


def copy_template_files(source_dir: Path, target_dir: Path, dry_run: bool, label: str) -> list[str]:
    actions: list[str] = []
    if not source_dir.exists():
        return actions
    for item in sorted(source_dir.glob("*")):
        if not item.is_file():
            continue
        destination = target_dir / item.name
        actions.append(f"{label}: {destination}")
        if dry_run:
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() and not filecmp.cmp(item, destination, shallow=False):
            shutil.copy2(destination, destination.with_suffix(destination.suffix + f".backup.{now()}"))
        shutil.copy2(item, destination)
    return actions


def opencode_config_root(scope: str, home: Path, project_dir: Path) -> Path:
    if scope == "global":
        return home / ".config" / "opencode"
    return project_dir / ".opencode"


def install_opencode_assets(source: Path, scope: str, home: Path, project_dir: Path, dry_run: bool) -> list[str]:
    config_root = opencode_config_root(scope, home, project_dir)
    template_root = source / "templates" / "opencode"
    actions: list[str] = []
    actions.extend(copy_template_files(template_root / "agents", config_root / "agents", dry_run, "opencode agent"))
    actions.extend(copy_template_files(template_root / "command", config_root / "command", dry_run, "opencode command"))
    return actions


def install(args: argparse.Namespace) -> int:
    source = skill_root()
    home = Path(args.home or os.environ.get("HOME", "~")).expanduser().resolve()
    project_dir = Path(args.project_dir).expanduser().resolve()
    target = target_path(args.harness, args.scope, home, project_dir)
    layout = LAYOUTS[args.harness]

    print(f"Installing {SKILL_NAME} for {layout['label']} ({args.scope})")
    print(f"Source: {source}")
    print(f"Target: {target}")

    if same_path(source, target):
        print("Target already is the canonical installed skill; no copy needed.")
    else:
        backup = backup_existing(target, args.dry_run)
        if backup:
            print(f"Backup: {backup}")
        if args.dry_run:
            print("Dry run: would copy skill files, excluding .deslop, .git, caches, and .DS_Store.")
        else:
            copy_tree(source, target)
            write_marker(target, args.harness, args.scope, source)
            print("Copied skill files.")

    extra_actions: list[str] = []
    if args.harness == "codex":
        extra_actions = install_codex_profiles(source, args.scope, home, project_dir, args.dry_run)
        for action in extra_actions:
            print(f"Installed {action}" if not args.dry_run else f"Dry run: would install {action}")
    if args.harness == "opencode":
        extra_actions = install_opencode_assets(source, args.scope, home, project_dir, args.dry_run)
        for action in extra_actions:
            print(f"Installed {action}" if not args.dry_run else f"Dry run: would install {action}")
        if extra_actions:
            print("OpenCode loads agent, command, and skill files at startup; restart OpenCode if it is already running.")

    scripts_dir = target / "scripts"
    runner_harness = layout["runner_harness"]
    print("Invocation:")
    if runner_harness:
        print(f"  DESLOP_HARNESS={runner_harness} {scripts_dir / 'deslop-review.sh'}")
        print(f"  DESLOP_HARNESS={runner_harness} {scripts_dir / 'deslop-loop.sh'} --max-iterations 5 --priority P0,P1")
    else:
        print(f"  Shared fallback installed at {target}; run with a concrete DESLOP_HARNESS adapter.")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Install ultimate-de-slop for a harness.")
    parser.add_argument("--harness", required=True, choices=sorted(LAYOUTS))
    parser.add_argument("--scope", choices=["global", "local"], default="global")
    parser.add_argument("--project-dir", default=os.getcwd())
    parser.add_argument("--home", help="Override HOME, useful for tests.")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(install(parse_args()))
