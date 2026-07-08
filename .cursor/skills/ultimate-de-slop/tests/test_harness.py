from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parents[1]
SCRIPT_DIR = SKILL_DIR / "scripts"


def run(
    args: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        args,
        cwd=cwd,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def write_executable(path: Path, text: str) -> None:
    path.write_text(text)
    path.chmod(0o755)


def init_repo(root: Path) -> None:
    run(["git", "init"], cwd=root, check=True)
    run(["git", "config", "user.email", "deslop@example.invalid"], cwd=root, check=True)
    run(["git", "config", "user.name", "Deslop Test"], cwd=root, check=True)
    (root / ".deslop").mkdir()
    (root / ".deslop" / "runs").mkdir()
    (root / ".deslop" / "config.json").write_text(
        json.dumps(
            {
                "max_fix_attempts": 3,
                "max_changed_files_per_fix": 8,
                "max_changed_lines_per_fix": 400,
            }
        )
        + "\n"
    )
    (root / ".deslop" / "inventory.json").write_text('{"detected_commands": []}\n')


def write_findings(root: Path, *findings: dict[str, object]) -> None:
    (root / ".deslop" / "findings.jsonl").write_text(
        "".join(json.dumps(finding, sort_keys=True) + "\n" for finding in findings)
    )


def read_finding(root: Path, finding_id: str) -> dict[str, object]:
    for line in (root / ".deslop" / "findings.jsonl").read_text().splitlines():
        finding = json.loads(line)
        if finding.get("id") == finding_id:
            return finding
    raise AssertionError(f"finding not found: {finding_id}")


def latest_run_file(root: Path, suffix: str, finding_id: str, filename: str) -> Path:
    matches = sorted((root / ".deslop" / "runs").glob(f"*-{suffix}-{finding_id}/{filename}"))
    if not matches:
        raise AssertionError(f"no {filename} found for {suffix} {finding_id}")
    return matches[-1]


def prepare_verify_fixture(root: Path, finding_id: str = "DSL-000001") -> Path:
    fix_dir = root / ".deslop" / "runs" / f"20260531T000000Z-fix-{finding_id}"
    fix_dir.mkdir(parents=True)
    status_before = fix_dir / "git-status-before.txt"
    diff_before = fix_dir / "git-diff-before.patch"
    status_after = fix_dir / "git-status-after.txt"
    diff_after = fix_dir / "git-diff-after.patch"
    attempt_delta = fix_dir / "git-diff-attempt.patch"
    status_before.write_text(" M sample.py\n")
    diff_before.write_text("")
    status_after.write_text(" M sample.py\n")
    diff_after.write_text("diff --git a/sample.py b/sample.py\n+value = 2\n")
    attempt_delta.write_text("+diff --git a/sample.py b/sample.py\n++value = 2\n")
    finding = minimal_finding(finding_id, files=["sample.py"])
    finding["status"] = "fixed_unverified"
    finding["last_fix"] = {
        "snapshot_paths": {
            "status_before": str(status_before),
            "diff_before": str(diff_before),
            "status_after": str(status_after),
            "diff_after": str(diff_after),
            "attempt_delta": str(attempt_delta),
        }
    }
    write_findings(root, finding)

    checks_dir = root / ".deslop" / "runs" / f"20260531T000100Z-checks-{finding_id}"
    checks_dir.mkdir()
    checks_path = checks_dir / "checks.json"
    checks_path.write_text(
        json.dumps({"finding_id": finding_id, "status": "passed", "results": []}) + "\n"
    )
    return checks_path


def write_fake_codex_verify(fake_bin: Path, payload: dict[str, object]) -> Path:
    fake_bin.mkdir(parents=True, exist_ok=True)
    fake_codex = fake_bin / "codex"
    fake_codex.write_text(
        f"""#!/usr/bin/env python3
import json
import sys
from pathlib import Path

payload = {json.dumps(payload)}
text = json.dumps(payload)
if "--output-last-message" in sys.argv:
    Path(sys.argv[sys.argv.index("--output-last-message") + 1]).write_text(text + "\\n")
print(text)
"""
    )
    fake_codex.chmod(0o755)
    return fake_codex


def minimal_finding(
    finding_id: str,
    *,
    expected_checks: list[str] | None = None,
    files: list[str] | None = None,
) -> dict[str, object]:
    return {
        "acceptance_criteria": ["shared helper is used by both callers"],
        "attempts": 0,
        "category": "test",
        "confidence": 0.99,
        "created_at": "2026-05-31T00:00:00Z",
        "dependencies": [],
        "estimated_effort": "small",
        "evidence": [{"claim": "test evidence", "file": "sample.py", "lines": "1"}],
        "expected_checks": expected_checks or [],
        "files": files or ["sample.py"],
        "id": finding_id,
        "proposed_fix": "test fix",
        "reviewer": "test",
        "risk": "low",
        "severity": "P1",
        "status": "accepted",
        "title": "Test finding",
        "updated_at": "2026-05-31T00:00:00Z",
        "why_it_matters": "test why",
    }


class HarnessTests(unittest.TestCase):
    def make_repo(self) -> tuple[tempfile.TemporaryDirectory[str], Path]:
        tempdir = tempfile.TemporaryDirectory()
        root = Path(tempdir.name)
        init_repo(root)
        return tempdir, root

    def test_safe_expected_checks_run_without_inventory_allowlist(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("value = 1\n")
            write_findings(
                root,
                minimal_finding(
                    "DSL-000001",
                    expected_checks=["python3 -m py_compile sample.py"],
                ),
            )

            result = run([str(SCRIPT_DIR / "deslop-run-checks.sh"), "DSL-000001"], cwd=root)

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            checks_path = sorted((root / ".deslop" / "runs").glob("*-checks-DSL-000001/checks.json"))[-1]
            checks = json.loads(checks_path.read_text())
            self.assertEqual(checks["status"], "passed")
            self.assertEqual(checks["results"][0]["status"], "passed")

    def test_inventory_excludes_deslop_harness_artifacts(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("value = 1\n")
            run(["git", "add", "sample.py"], cwd=root, check=True)
            run(["git", "commit", "-m", "sample"], cwd=root, check=True)
            review_dir = root / ".deslop" / "runs" / "20260601T000000Z-review"
            review_dir.mkdir(parents=True)
            (review_dir / "raw-review-output.txt").write_text("agent output\n")
            (root / ".deslop" / "tmp" / "scratch.txt").parent.mkdir(parents=True, exist_ok=True)
            (root / ".deslop" / "tmp" / "scratch.txt").write_text("scratch\n")

            result = run([str(SCRIPT_DIR / "deslop-inventory.py"), "--write"], cwd=root)

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            inventory = json.loads((root / ".deslop" / "inventory.json").read_text())
            scanned_paths = {item["path"] for item in inventory["largest_files"]}
            scanned_paths.update(item["path"] for item in inventory["todo_fixme_counts"]["files"])
            scanned_paths.update(inventory["detected_tooling_files"])
            self.assertEqual(inventory["candidate_file_count"], 1)
            self.assertEqual(scanned_paths, {"sample.py"})

    def test_inventory_detects_py_compile_for_python_without_test_tooling(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("value = 1\n")
            (root / "pkg").mkdir()
            (root / "pkg" / "module.py").write_text("value = 2\n")
            run(["git", "add", "."], cwd=root, check=True)
            run(["git", "commit", "-m", "sample"], cwd=root, check=True)

            result = run([str(SCRIPT_DIR / "deslop-inventory.py"), "--write"], cwd=root)

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            inventory = json.loads((root / ".deslop" / "inventory.json").read_text())
            commands = {item["name"]: item["command"] for item in inventory["detected_commands"]}
            self.assertEqual(commands["py_compile"], "python3 -m py_compile pkg/module.py sample.py")

    def test_inventory_uses_safe_npm_prefix_for_nested_package_scripts(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            package_dir = root / "samples" / "app"
            package_dir.mkdir(parents=True)
            (package_dir / "package.json").write_text(
                json.dumps({"scripts": {"test": "node --test"}}) + "\n"
            )
            run(["git", "add", "."], cwd=root, check=True)
            run(["git", "commit", "-m", "sample"], cwd=root, check=True)

            result = run([str(SCRIPT_DIR / "deslop-inventory.py"), "--write"], cwd=root)

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            inventory = json.loads((root / ".deslop" / "inventory.json").read_text())
            commands = {item["name"]: item["command"] for item in inventory["detected_commands"]}
            self.assertEqual(commands["npm test"], "npm --prefix samples/app run test")

    def test_unavailable_pytest_expected_check_falls_back_to_py_compile(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("value = 1\n")
            (root / ".deslop" / "inventory.json").write_text(
                json.dumps(
                    {
                        "detected_commands": [
                            {"name": "pytest", "command": "python3 -m pytest", "source": "python"},
                            {"name": "py_compile", "command": "python3 -m py_compile sample.py", "source": "python"},
                        ]
                    }
                )
                + "\n"
            )
            write_findings(
                root,
                minimal_finding("DSL-000001", expected_checks=["python3 -m pytest"]),
            )

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "python3",
                f"""#!/usr/bin/env bash
if [ "$1" = "-m" ] && [ "$2" = "pytest" ]; then
  echo "No module named pytest" >&2
  exit 1
fi
exec {shlex.quote(sys.executable)} "$@"
""",
            )

            result = run(
                [str(SCRIPT_DIR / "deslop-run-checks.sh"), "DSL-000001"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            checks_path = sorted((root / ".deslop" / "runs").glob("*-checks-DSL-000001/checks.json"))[-1]
            checks = json.loads(checks_path.read_text())
            self.assertEqual(checks["status"], "passed")
            self.assertEqual(checks["results"][0]["command"], "python3 -m py_compile sample.py")

    def test_unsafe_expected_checks_stay_blocked(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            sentinel = root / "sentinel.txt"
            sentinel.write_text("still here\n")
            write_findings(
                root,
                minimal_finding("DSL-000001", expected_checks=["rm -rf sentinel.txt"]),
            )

            result = run([str(SCRIPT_DIR / "deslop-run-checks.sh"), "--no-fail", "DSL-000001"], cwd=root)

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(sentinel.read_text(), "still here\n")
            checks_path = sorted((root / ".deslop" / "runs").glob("*-checks-DSL-000001/checks.json"))[-1]
            checks = json.loads(checks_path.read_text())
            self.assertEqual(checks["status"], "failed")
            self.assertEqual(checks["results"][0]["status"], "blocked")

    def test_fix_does_not_treat_preexisting_dirty_tree_as_success(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("value = 1\n")
            run(["git", "add", "."], cwd=root, check=True)
            run(["git", "commit", "-m", "initial"], cwd=root, check=True)
            (root / "unrelated.txt").write_text("pre-existing dirty state\n")
            write_findings(root, minimal_finding("DSL-000001"))

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            fake_codex = fake_bin / "codex"
            fake_codex.write_text(
                """#!/usr/bin/env python3
import json
import sys
from pathlib import Path

payload = {
    "finding_id": "DSL-000001",
    "summary": "reported success without edits",
    "changed_files": [],
    "checks_run": [],
    "risks": [],
    "status": "fixed",
}
text = json.dumps(payload)
if "--output-last-message" in sys.argv:
    Path(sys.argv[sys.argv.index("--output-last-message") + 1]).write_text(text + "\\n")
print(text)
"""
            )
            fake_codex.chmod(0o755)

            result = run(
                [str(SCRIPT_DIR / "deslop-fix.sh"), "--allow-dirty", "DSL-000001"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertNotEqual(result.returncode, 0)
            finding = read_finding(root, "DSL-000001")
            self.assertEqual(finding["status"], "blocked")
            self.assertIn("no changed files", str(finding.get("block_reason", "")))

    def test_codex_runner_records_timeout(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            prompt = root / "prompt.txt"
            prompt.write_text("Return JSON.\n")
            raw = root / "raw.txt"
            last = root / "last.txt"
            runner_json = root / "runner.json"

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            fake_codex = fake_bin / "codex"
            fake_codex.write_text("#!/usr/bin/env bash\nsleep 5\n")
            fake_codex.chmod(0o755)

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-codex-runner.py"),
                    "--root",
                    str(root),
                    "--prompt",
                    str(prompt),
                    "--raw-output",
                    str(raw),
                    "--last-message",
                    str(last),
                    "--runner-json",
                    str(runner_json),
                    "--schema",
                    str(SKILL_DIR / "references" / "fix.schema.json"),
                    "--sandbox",
                    "read-only",
                ],
                cwd=root,
                env={
                    "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
                    "DESLOP_CODEX_TIMEOUT_SECONDS": "0.2",
                    "DESLOP_CODEX_IDLE_TIMEOUT_SECONDS": "10",
                },
            )

            self.assertEqual(result.returncode, 124)
            diagnostics = json.loads(runner_json.read_text())
            self.assertEqual(diagnostics["status"], "wall_timeout")
            self.assertIs(diagnostics["timed_out"], True)

    def test_agent_runner_constructs_opencode_command(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            prompt = root / "prompt.txt"
            prompt.write_text("Return JSON.\n")
            raw = root / "raw.txt"
            last = root / "last.txt"
            runner_json = root / "runner.json"

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "opencode",
                """#!/usr/bin/env python3
import json
import sys

payload = {"ok": True, "argv": sys.argv[1:], "stdin": sys.stdin.read()}
print(json.dumps(payload))
""",
            )

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-agent-runner.py"),
                    "--root",
                    str(root),
                    "--prompt",
                    str(prompt),
                    "--raw-output",
                    str(raw),
                    "--last-message",
                    str(last),
                    "--runner-json",
                    str(runner_json),
                    "--schema",
                    str(SKILL_DIR / "references" / "review.schema.json"),
                    "--sandbox",
                    "read-only",
                    "--kind",
                    "review",
                ],
                cwd=root,
                env={
                    "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
                    "DESLOP_HARNESS": "opencode",
                    "DESLOP_MODEL": "test-model",
                },
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            diagnostics = json.loads(runner_json.read_text())
            self.assertEqual(diagnostics["harness"], "opencode")
            self.assertEqual(diagnostics["status"], "completed")
            self.assertEqual(diagnostics["model"], "test-model")
            command = diagnostics["command"]
            self.assertEqual(command[:2], ["opencode", "run"])
            self.assertIn("--dir", command)
            self.assertIn(str(root.resolve()), command)
            self.assertIn("--agent", command)
            self.assertIn("deslop_reviewer", command)
            self.assertEqual(last.read_text(), raw.read_text())

    def test_agent_runner_extracts_opencode_text_events_to_last_message(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            prompt = root / "prompt.txt"
            prompt.write_text("Return JSON.\n")
            raw = root / "raw.txt"
            last = root / "last.txt"
            runner_json = root / "runner.json"
            payload = {
                "repo_summary": "event-stream review",
                "review_wave_id": "wave-event",
                "partitions_reviewed": ["root"],
                "findings": [],
            }

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            fake_opencode = fake_bin / "opencode"
            fake_opencode.write_text(
                f"""#!/usr/bin/env python3
import json

print(json.dumps({{"type": "step_start", "part": {{"type": "step-start"}}}}))
print(json.dumps({{"type": "text", "part": {{"type": "text", "text": {json.dumps(json.dumps(payload))}}}}}))
print(json.dumps({{"type": "step_finish", "part": {{"type": "step-finish"}}}}))
"""
            )
            fake_opencode.chmod(0o755)

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-agent-runner.py"),
                    "--root",
                    str(root),
                    "--prompt",
                    str(prompt),
                    "--raw-output",
                    str(raw),
                    "--last-message",
                    str(last),
                    "--runner-json",
                    str(runner_json),
                    "--schema",
                    str(SKILL_DIR / "references" / "review.schema.json"),
                    "--sandbox",
                    "read-only",
                    "--kind",
                    "review",
                ],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}", "DESLOP_HARNESS": "opencode"},
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn('"type": "text"', raw.read_text())
            self.assertEqual(json.loads(last.read_text()), payload)

    def test_agent_runner_extracts_pi_turn_end_text_to_last_message(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            prompt = root / "prompt.txt"
            prompt.write_text("Return JSON.\n")
            raw = root / "raw.txt"
            last = root / "last.txt"
            runner_json = root / "runner.json"
            payload = {
                "repo_summary": "pi event-stream review",
                "review_wave_id": "wave-pi",
                "partitions_reviewed": ["root"],
                "findings": [],
            }

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            fake_pi = fake_bin / "pi"
            fake_pi.write_text(
                f"""#!/usr/bin/env python3
import json

print(json.dumps({{"type": "message_update", "assistantMessageEvent": {{"type": "text_delta", "delta": "noise"}}}}))
print(json.dumps({{"type": "turn_end", "message": {{"role": "assistant", "content": [{{"type": "thinking", "thinking": "ignored"}}, {{"type": "text", "text": {json.dumps(json.dumps(payload))}}}]}}}}))
"""
            )
            fake_pi.chmod(0o755)

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-agent-runner.py"),
                    "--root",
                    str(root),
                    "--prompt",
                    str(prompt),
                    "--raw-output",
                    str(raw),
                    "--last-message",
                    str(last),
                    "--runner-json",
                    str(runner_json),
                    "--schema",
                    str(SKILL_DIR / "references" / "review.schema.json"),
                    "--sandbox",
                    "read-only",
                    "--kind",
                    "review",
                ],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}", "DESLOP_HARNESS": "pi"},
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn('"turn_end"', raw.read_text())
            self.assertEqual(json.loads(last.read_text()), payload)
            diagnostics = json.loads(runner_json.read_text())
            self.assertIn("--thinking", diagnostics["command"])
            thinking_index = diagnostics["command"].index("--thinking")
            self.assertEqual(diagnostics["command"][thinking_index + 1], "off")

    def test_agent_runner_extracts_cursor_result_to_last_message(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            prompt = root / "prompt.txt"
            prompt.write_text("Return JSON.\n")
            raw = root / "raw.txt"
            last = root / "last.txt"
            runner_json = root / "runner.json"
            payload = {
                "repo_summary": "cursor wrapped review",
                "review_wave_id": "wave-cursor",
                "partitions_reviewed": ["root"],
                "findings": [],
            }

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "cursor-agent",
                f"""#!/usr/bin/env python3
import json

print(json.dumps({{
    "type": "result",
    "subtype": "success",
    "is_error": False,
    "result": {json.dumps(json.dumps(payload))},
}}))
""",
            )

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-agent-runner.py"),
                    "--root",
                    str(root),
                    "--prompt",
                    str(prompt),
                    "--raw-output",
                    str(raw),
                    "--last-message",
                    str(last),
                    "--runner-json",
                    str(runner_json),
                    "--schema",
                    str(SKILL_DIR / "references" / "review.schema.json"),
                    "--sandbox",
                    "read-only",
                    "--kind",
                    "review",
                ],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}", "DESLOP_HARNESS": "cursor"},
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn('"type": "result"', raw.read_text())
            self.assertEqual(json.loads(last.read_text()), payload)

    def test_agent_runner_extracts_claude_result_to_last_message(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            prompt = root / "prompt.txt"
            prompt.write_text("Return JSON.\n")
            raw = root / "raw.txt"
            last = root / "last.txt"
            runner_json = root / "runner.json"
            payload = {
                "repo_summary": "claude wrapped review",
                "review_wave_id": "wave-claude",
                "partitions_reviewed": ["root"],
                "findings": [],
            }

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "claude",
                f"""#!/usr/bin/env python3
import json

print(json.dumps({{
    "type": "result",
    "subtype": "success",
    "is_error": False,
    "result": {json.dumps(f"Here is the review JSON.\n```json\n{json.dumps(payload)}\n```")},
    "modelUsage": {{"claude-haiku-4-5": {{"inputTokens": 1, "outputTokens": 1}}}},
}}))
""",
            )

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-agent-runner.py"),
                    "--root",
                    str(root),
                    "--prompt",
                    str(prompt),
                    "--raw-output",
                    str(raw),
                    "--last-message",
                    str(last),
                    "--runner-json",
                    str(runner_json),
                    "--schema",
                    str(SKILL_DIR / "references" / "review.schema.json"),
                    "--sandbox",
                    "read-only",
                    "--kind",
                    "review",
                ],
                cwd=root,
                env={
                    "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
                    "DESLOP_HARNESS": "claude",
                    "DESLOP_MODEL": "claude-haiku-4-5",
                },
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn('"type": "result"', raw.read_text())
            self.assertEqual(json.loads(last.read_text().split("```json\n", 1)[1].split("\n```", 1)[0]), payload)
            diagnostics = json.loads(runner_json.read_text())
            self.assertEqual(diagnostics["model"], "claude-haiku-4-5")
            self.assertEqual(diagnostics["permission_mode"], "default")
            self.assertNotIn("plan", diagnostics["command"])

    def test_agent_runner_enables_write_permissions_for_headless_fixers(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            prompt = root / "prompt.txt"
            prompt.write_text("Return JSON.\n")
            raw = root / "raw.txt"
            last = root / "last.txt"
            runner_json = root / "runner.json"

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            for cli_name in ("cursor-agent", "commandcode"):
                write_executable(
                    fake_bin / cli_name,
                    """#!/usr/bin/env python3
import json

payload = {
    "finding_id": "DSL-000001",
    "summary": "test",
    "changed_files": [],
    "checks_run": [],
    "risks": [],
    "status": "fixed",
}
print(json.dumps(payload))
""",
                )

            for harness, expected_flag in (("cursor", "--force"), ("commandcode", "--yolo")):
                with self.subTest(harness=harness):
                    raw.unlink(missing_ok=True)
                    last.unlink(missing_ok=True)
                    runner_json.unlink(missing_ok=True)

                    result = run(
                        [
                            sys.executable,
                            str(SCRIPT_DIR / "deslop-agent-runner.py"),
                            "--root",
                            str(root),
                            "--prompt",
                            str(prompt),
                            "--raw-output",
                            str(raw),
                            "--last-message",
                            str(last),
                            "--runner-json",
                            str(runner_json),
                            "--schema",
                            str(SKILL_DIR / "references" / "fix.schema.json"),
                            "--sandbox",
                            "workspace-write",
                            "--kind",
                            "fix",
                        ],
                        cwd=root,
                        env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}", "DESLOP_HARNESS": harness},
                    )

                    self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                    diagnostics = json.loads(runner_json.read_text())
                    self.assertIn(expected_flag, diagnostics["command"])

    def test_agent_runner_records_missing_cli(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            prompt = root / "prompt.txt"
            prompt.write_text("Return JSON.\n")
            raw = root / "raw.txt"
            last = root / "last.txt"
            runner_json = root / "runner.json"
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-agent-runner.py"),
                    "--root",
                    str(root),
                    "--prompt",
                    str(prompt),
                    "--raw-output",
                    str(raw),
                    "--last-message",
                    str(last),
                    "--runner-json",
                    str(runner_json),
                    "--schema",
                    str(SKILL_DIR / "references" / "review.schema.json"),
                    "--sandbox",
                    "read-only",
                    "--kind",
                    "review",
                ],
                cwd=root,
                env={"PATH": str(fake_bin), "DESLOP_HARNESS": "claude"},
            )

            self.assertEqual(result.returncode, 127)
            diagnostics = json.loads(runner_json.read_text())
            self.assertEqual(diagnostics["status"], "claude_not_found")
            self.assertIs(diagnostics["missing_cli"], True)
            self.assertIn("claude CLI not found", raw.read_text())
            self.assertEqual(last.read_text(), raw.read_text())

    def test_agent_runner_records_idle_timeout(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            prompt = root / "prompt.txt"
            prompt.write_text("Return JSON.\n")
            raw = root / "raw.txt"
            last = root / "last.txt"
            runner_json = root / "runner.json"

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "codex",
                """#!/usr/bin/env python3
import sys
import time

print("starting", flush=True)
time.sleep(5)
""",
            )

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-agent-runner.py"),
                    "--root",
                    str(root),
                    "--prompt",
                    str(prompt),
                    "--raw-output",
                    str(raw),
                    "--last-message",
                    str(last),
                    "--runner-json",
                    str(runner_json),
                    "--schema",
                    str(SKILL_DIR / "references" / "fix.schema.json"),
                    "--sandbox",
                    "read-only",
                    "--kind",
                    "review",
                ],
                cwd=root,
                env={
                    "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
                    "DESLOP_HARNESS": "codex",
                    "DESLOP_TIMEOUT_SECONDS": "10",
                    "DESLOP_IDLE_TIMEOUT_SECONDS": "0.2",
                },
            )

            self.assertEqual(result.returncode, 125)
            diagnostics = json.loads(runner_json.read_text())
            self.assertEqual(diagnostics["status"], "idle_timeout")
            self.assertIs(diagnostics["idle_timed_out"], True)
            self.assertIn("idle timeout", raw.read_text())

    def test_review_extracts_json_from_raw_when_last_message_is_not_json(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("value = 1\n")
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "codex",
                """#!/usr/bin/env python3
import json
import sys
from pathlib import Path

payload = {
    "repo_summary": "empty test review",
    "review_wave_id": "wave-test",
    "partitions_reviewed": ["root"],
    "findings": [],
}
if "--output-last-message" in sys.argv:
    Path(sys.argv[sys.argv.index("--output-last-message") + 1]).write_text("not json\\n")
print("prefix")
print(json.dumps(payload))
print("suffix")
""",
            )

            result = run(
                [str(SCRIPT_DIR / "deslop-review.sh")],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            review_paths = sorted((root / ".deslop" / "runs").glob("*-review/review.json"))
            self.assertTrue(review_paths)
            review = json.loads(review_paths[-1].read_text())
            self.assertEqual(review["review_wave_id"], "wave-test")
            prompt = sorted((root / ".deslop" / "runs").glob("*-review/prompt.txt"))[-1].read_text()
            self.assertIn("Do not inspect `.deslop/runs`", prompt)
            self.assertIn('"repo_summary"', prompt)
            self.assertIn("Use `severity`, not `priority`", prompt)
            self.assertNotIn("Use $ultimate-de-slop", prompt)

    def test_review_extraction_rejects_json_missing_required_review_keys(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("value = 1\n")
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "codex",
                """#!/usr/bin/env python3
import sys
from pathlib import Path

if "--output-last-message" in sys.argv:
    Path(sys.argv[sys.argv.index("--output-last-message") + 1]).write_text('{"findings": []}\\n')
print('{"nested": "not review output"}')
""",
            )

            result = run(
                [str(SCRIPT_DIR / "deslop-review.sh")],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("JSON extraction failed", result.stderr)
            review_paths = sorted((root / ".deslop" / "runs").glob("*-review/review.json"))
            self.assertFalse(review_paths)

    def test_review_extraction_repairs_invalid_single_quote_escapes(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("value = 1\n")
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "codex",
                r"""#!/usr/bin/env python3
import sys
from pathlib import Path

text = r'''prefix
{
  "repo_summary": "test",
  "review_wave_id": "wave-test",
  "partitions_reviewed": ["root"],
  "findings": [{
    "title": "escaped quote",
    "severity": "P1",
    "confidence": 0.95,
    "category": "correctness",
    "files": ["sample.py"],
    "evidence": [{"file": "sample.py", "lines": "1", "symbol": "value", "claim": "query = f\'bad\'"}],
    "why_it_matters": "test",
    "proposed_fix": "test",
    "acceptance_criteria": ["test"],
    "expected_checks": ["python3 -m py_compile sample.py"],
    "risk": "low",
    "estimated_effort": "small"
  }]
}
suffix'''
if "--output-last-message" in sys.argv:
    Path(sys.argv[sys.argv.index("--output-last-message") + 1]).write_text("not json\n")
print(text)
""",
            )

            result = run(
                [str(SCRIPT_DIR / "deslop-review.sh")],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            review_paths = sorted((root / ".deslop" / "runs").glob("*-review/review.json"))
            review = json.loads(review_paths[-1].read_text())
            self.assertIn("f'bad'", review["findings"][0]["evidence"][0]["claim"])

    def test_arbitrate_normalizes_common_model_review_variants(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("def broken():\n    pass\n")
            run(["git", "add", "sample.py"], cwd=root, check=True)
            run(["git", "commit", "-m", "sample"], cwd=root, check=True)
            review = {
                "repo_summary": "test repo",
                "review_wave_id": "wave-test",
                "partitions_reviewed": ["root"],
                "findings": [
                    {
                        "id": "F1",
                        "title": "broken returns nothing",
                        "priority": "P1",
                        "confidence": "high",
                        "category": "correctness",
                        "files": "sample.py",
                        "evidence": {"sample.py": "broken only contains pass"},
                        "why_it_matters": "callers receive None instead of a useful value",
                        "proposed_fix": "return a deterministic value from the function",
                        "acceptance_criteria": "broken returns a useful value",
                        "expected_checks": "python -m py_compile sample.py",
                        "risk": "Low",
                        "effort": "S",
                    }
                ],
            }
            review_path = root / "review.json"
            review_path.write_text(json.dumps(review) + "\n")

            result = run(
                [str(SCRIPT_DIR / "deslop-arbitrate.py"), str(review_path), "--json"],
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            outcome = json.loads(result.stdout)
            self.assertEqual(len(outcome["accepted"]), 1)
            finding = read_finding(root, outcome["accepted"][0])
            self.assertEqual(finding["severity"], "P1")
            self.assertEqual(finding["confidence"], 0.95)
            self.assertEqual(finding["estimated_effort"], "small")
            self.assertEqual(finding["risk"], "low")
            self.assertEqual(finding["acceptance_criteria"], ["broken returns a useful value"])
            self.assertEqual(finding["expected_checks"], ["python -m py_compile sample.py"])
            self.assertEqual(finding["evidence"][0]["file"], "sample.py")
            self.assertIn("broken only contains pass", finding["evidence"][0]["claim"])

    def test_arbitrate_scrubs_non_allowlisted_expected_checks(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("def broken():\n    pass\n")
            run(["git", "add", "sample.py"], cwd=root, check=True)
            run(["git", "commit", "-m", "sample"], cwd=root, check=True)
            review = {
                "repo_summary": "test repo",
                "review_wave_id": "wave-test",
                "partitions_reviewed": ["root"],
                "findings": [
                    {
                        "title": "unsafe check command",
                        "severity": "P1",
                        "confidence": 0.95,
                        "category": "correctness",
                        "files": ["sample.py"],
                        "evidence": [{"file": "sample.py", "claim": "broken only contains pass"}],
                        "why_it_matters": "callers receive None instead of a useful value",
                        "proposed_fix": "return a deterministic value from the function",
                        "acceptance_criteria": ["broken returns a useful value"],
                        "expected_checks": [
                            "python3 -c \"open('sentinel', 'w').write('unsafe')\"",
                            "python3 -m py_compile sample.py",
                        ],
                        "risk": "low",
                        "estimated_effort": "small",
                    }
                ],
            }
            review_path = root / "review.json"
            review_path.write_text(json.dumps(review) + "\n")

            result = run(
                [str(SCRIPT_DIR / "deslop-arbitrate.py"), str(review_path), "--json"],
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            outcome = json.loads(result.stdout)
            finding = read_finding(root, outcome["accepted"][0])
            self.assertEqual(finding["expected_checks"], ["python3 -m py_compile sample.py"])
            self.assertIn("Removed non-allowlisted expected_checks", finding["expected_checks_explanation"])

    def test_arbitrate_scrubs_ambiguous_grep_expected_checks(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("def broken():\n    pass\n")
            run(["git", "add", "sample.py"], cwd=root, check=True)
            run(["git", "commit", "-m", "sample"], cwd=root, check=True)
            review = {
                "repo_summary": "test repo",
                "review_wave_id": "wave-test",
                "partitions_reviewed": ["root"],
                "findings": [
                    {
                        "title": "ambiguous grep check",
                        "severity": "P1",
                        "confidence": 0.95,
                        "category": "correctness",
                        "files": ["sample.py"],
                        "evidence": [{"file": "sample.py", "lines": "2", "claim": "broken only contains pass"}],
                        "why_it_matters": "callers receive None instead of a useful value",
                        "proposed_fix": "return a deterministic value from the function",
                        "acceptance_criteria": ["broken returns a useful value"],
                        "expected_checks": ["grep -r \"pass\" sample.py"],
                        "risk": "low",
                        "estimated_effort": "small",
                    }
                ],
            }
            review_path = root / "review.json"
            review_path.write_text(json.dumps(review) + "\n")

            result = run(
                [str(SCRIPT_DIR / "deslop-arbitrate.py"), str(review_path), "--json"],
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            outcome = json.loads(result.stdout)
            finding = read_finding(root, outcome["accepted"][0])
            self.assertEqual(finding["expected_checks"], [])
            self.assertIn("Removed non-allowlisted expected_checks", finding["no_expected_checks_reason"])

    def test_arbitrate_scrubs_npm_test_with_extra_path_args(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "package.json").write_text(json.dumps({"scripts": {"test": "node --test"}}) + "\n")
            (root / "sample.js").write_text("export function broken() { return null; }\n")
            run(["git", "add", "."], cwd=root, check=True)
            run(["git", "commit", "-m", "sample"], cwd=root, check=True)
            review = {
                "repo_summary": "test repo",
                "review_wave_id": "wave-test",
                "partitions_reviewed": ["root"],
                "findings": [
                    {
                        "title": "bad targeted package check",
                        "severity": "P1",
                        "confidence": 0.95,
                        "category": "correctness",
                        "files": ["sample.js"],
                        "evidence": [{"file": "sample.js", "lines": "1", "claim": "broken returns null"}],
                        "why_it_matters": "callers receive no useful value",
                        "proposed_fix": "return a useful value",
                        "acceptance_criteria": ["broken returns a useful value"],
                        "expected_checks": ["npm test sample.js", "npm run test"],
                        "risk": "low",
                        "estimated_effort": "small",
                    }
                ],
            }
            review_path = root / "review.json"
            review_path.write_text(json.dumps(review) + "\n")

            result = run(
                [str(SCRIPT_DIR / "deslop-arbitrate.py"), str(review_path), "--json"],
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            outcome = json.loads(result.stdout)
            finding = read_finding(root, outcome["accepted"][0])
            self.assertEqual(finding["expected_checks"], ["npm run test"])
            self.assertIn("Removed non-allowlisted expected_checks", finding["expected_checks_explanation"])

    def test_arbitrate_rejects_speculative_filename_only_evidence(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "hardcoded_credentials.py").write_text("API_KEY = 'test'\n")
            run(["git", "add", "hardcoded_credentials.py"], cwd=root, check=True)
            run(["git", "commit", "-m", "sample"], cwd=root, check=True)
            review = {
                "repo_summary": "test repo",
                "review_wave_id": "wave-test",
                "partitions_reviewed": ["root"],
                "findings": [
                    {
                        "title": "hardcoded credentials likely embedded",
                        "severity": "P0",
                        "confidence": 0.95,
                        "category": "security/boundaries",
                        "files": ["hardcoded_credentials.py"],
                        "evidence": [
                            {
                                "file": "hardcoded_credentials.py",
                                "claim": "File is flagged as a hardcoded credential vulnerability candidate; likely contains literal secrets.",
                            }
                        ],
                        "why_it_matters": "hardcoded credentials leak access",
                        "proposed_fix": "remove embedded secrets and load from environment variables",
                        "acceptance_criteria": ["no literal secrets remain"],
                        "expected_checks": ["python3 -m py_compile hardcoded_credentials.py"],
                        "risk": "high",
                        "estimated_effort": "small",
                    }
                ],
            }
            review_path = root / "review.json"
            review_path.write_text(json.dumps(review) + "\n")

            result = run(
                [str(SCRIPT_DIR / "deslop-arbitrate.py"), str(review_path), "--json"],
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            outcome = json.loads(result.stdout)
            self.assertEqual(outcome["accepted"], [])
            self.assertIn("evidence is speculative", outcome["rejected"][0]["reasons"][0])

    def test_codex_runner_shim_keeps_codex_exec_contract(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            prompt = root / "prompt.txt"
            prompt.write_text("Return JSON.\n")
            raw = root / "raw.txt"
            last = root / "last.txt"
            runner_json = root / "runner.json"
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "codex",
                """#!/usr/bin/env python3
import json
import sys
from pathlib import Path

if "--output-last-message" in sys.argv:
    Path(sys.argv[sys.argv.index("--output-last-message") + 1]).write_text("{}\\n")
print(json.dumps({"argv": sys.argv[1:]}))
""",
            )

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-codex-runner.py"),
                    "--root",
                    str(root),
                    "--prompt",
                    str(prompt),
                    "--raw-output",
                    str(raw),
                    "--last-message",
                    str(last),
                    "--runner-json",
                    str(runner_json),
                    "--schema",
                    str(SKILL_DIR / "references" / "fix.schema.json"),
                    "--sandbox",
                    "workspace-write",
                    "--kind",
                    "fix",
                    "--add-dir",
                    str(root / ".deslop"),
                ],
                cwd=root,
                env={
                    "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
                    "DESLOP_HARNESS": "claude",
                    "DESLOP_CODEX_MODEL": "legacy-model",
                },
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            diagnostics = json.loads(runner_json.read_text())
            command = diagnostics["command"]
            self.assertEqual(diagnostics["harness"], "codex")
            self.assertEqual(command[:4], ["codex", "exec", "-m", "legacy-model"])
            self.assertIn("--output-schema", command)
            self.assertIn("--output-last-message", command)
            self.assertIn("--add-dir", command)

    def test_openclaw_adapter_fails_with_tested_actionable_mode_when_cli_exists(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            prompt = root / "prompt.txt"
            prompt.write_text("Return JSON.\n")
            raw = root / "raw.txt"
            last = root / "last.txt"
            runner_json = root / "runner.json"
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(fake_bin / "openclaw", "#!/usr/bin/env bash\nexit 99\n")

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-agent-runner.py"),
                    "--root",
                    str(root),
                    "--prompt",
                    str(prompt),
                    "--raw-output",
                    str(raw),
                    "--last-message",
                    str(last),
                    "--runner-json",
                    str(runner_json),
                    "--schema",
                    str(SKILL_DIR / "references" / "review.schema.json"),
                    "--sandbox",
                    "read-only",
                    "--kind",
                    "review",
                ],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}", "DESLOP_HARNESS": "openclaw"},
            )

            self.assertEqual(result.returncode, 126)
            diagnostics = json.loads(runner_json.read_text())
            self.assertEqual(diagnostics["status"], "openclaw_unsupported")
            self.assertIn("not confirmed", diagnostics["unsupported_reason"])
            self.assertIn("intentionally fails", raw.read_text())

    def test_installer_local_copy_excludes_runtime_and_caches(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            result = run(
                [
                    str(SCRIPT_DIR / "install" / "install-claude.sh"),
                    "--scope",
                    "local",
                    "--project-dir",
                    str(root),
                    "--home",
                    str(root / "home"),
                ],
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            target = root / ".claude" / "skills" / "ultimate-de-slop"
            self.assertTrue((target / "SKILL.md").exists())
            self.assertTrue((target / "scripts" / "deslop-agent-runner.py").exists())
            self.assertFalse((target / ".deslop").exists())
            self.assertFalse((target / "tests" / "__pycache__").exists())
            self.assertIn("DESLOP_HARNESS=claude", result.stdout)

    def test_opencode_global_installer_uses_config_home_and_installs_native_assets(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            home = root / "home"
            result = run(
                [
                    str(SCRIPT_DIR / "install" / "install-opencode.sh"),
                    "--home",
                    str(home),
                ],
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            target = home / ".config" / "opencode" / "skills" / "ultimate-de-slop"
            self.assertTrue((target / "SKILL.md").exists())
            self.assertTrue((target / "scripts" / "deslop-agent-runner.py").exists())
            self.assertFalse((home / ".opencode" / "skills" / "ultimate-de-slop").exists())
            reviewer = home / ".config" / "opencode" / "agents" / "deslop_reviewer.md"
            self.assertTrue(reviewer.exists())
            reviewer_text = reviewer.read_text()
            self.assertIn("mode: primary", reviewer_text)
            self.assertIn("skill: deny", reviewer_text)
            self.assertIn("shell: deny", reviewer_text)
            self.assertTrue((home / ".config" / "opencode" / "agents" / "deslop_fixer.md").exists())
            self.assertTrue((home / ".config" / "opencode" / "command" / "ultimate-de-slop.md").exists())
            self.assertIn("OpenCode loads agent, command, and skill files at startup", result.stdout)

    def test_installer_dry_run_does_not_write_home(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            home = root / "home"
            result = run(
                [
                    str(SCRIPT_DIR / "install" / "install-cursor.sh"),
                    "--dry-run",
                    "--home",
                    str(home),
                ],
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("Dry run", result.stdout)
            self.assertFalse((home / ".cursor").exists())

    def test_runner_output_schemas_are_strict_compatible(self) -> None:
        schema_names = [
            "arbiter.schema.json",
            "fix.schema.json",
            "review.schema.json",
            "verify.schema.json",
        ]

        def visit_schema_objects(schema: dict[str, object]):
            stack = [schema]
            while stack:
                current = stack.pop()
                if not isinstance(current, dict):
                    continue
                if current.get("type") == "object" and "properties" in current:
                    yield current
                for key in ("properties", "$defs"):
                    children = current.get(key)
                    if isinstance(children, dict):
                        stack.extend(item for item in children.values() if isinstance(item, dict))
                items = current.get("items")
                if isinstance(items, dict):
                    stack.append(items)

        for schema_name in schema_names:
            with self.subTest(schema=schema_name):
                schema = json.loads((SKILL_DIR / "references" / schema_name).read_text())
                for obj in visit_schema_objects(schema):
                    properties = obj.get("properties")
                    self.assertIsInstance(properties, dict)
                    self.assertIs(obj.get("additionalProperties"), False)
                    self.assertEqual(sorted(obj.get("required", [])), sorted(properties.keys()))

    def test_fix_records_per_attempt_diff_snapshots(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "baseline.py").write_text("value = 'clean'\n")
            (root / "sample.py").write_text("value = 1\n")
            run(["git", "add", "."], cwd=root, check=True)
            run(["git", "commit", "-m", "initial"], cwd=root, check=True)
            (root / "baseline.py").write_text("value = 'preexisting dirty change'\n")
            write_findings(root, minimal_finding("DSL-000001", files=["sample.py"]))

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            fake_codex = fake_bin / "codex"
            fake_codex.write_text(
                """#!/usr/bin/env python3
import json
import sys
from pathlib import Path

Path("sample.py").write_text("value = 2\\n")
payload = {
    "finding_id": "DSL-000001",
    "summary": "updated sample",
    "changed_files": ["sample.py"],
    "checks_run": [],
    "risks": [],
    "status": "fixed",
}
text = json.dumps(payload)
if "--output-last-message" in sys.argv:
    Path(sys.argv[sys.argv.index("--output-last-message") + 1]).write_text(text + "\\n")
print(text)
"""
            )
            fake_codex.chmod(0o755)

            result = run(
                [str(SCRIPT_DIR / "deslop-fix.sh"), "--allow-dirty", "DSL-000001"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            finding = read_finding(root, "DSL-000001")
            last_fix = finding["last_fix"]
            self.assertIsInstance(last_fix, dict)
            snapshots = last_fix["snapshot_paths"]
            self.assertIsInstance(snapshots, dict)
            for key in ("status_before", "diff_before", "status_after", "diff_after", "attempt_delta"):
                self.assertTrue(Path(snapshots[key]).exists(), key)
            self.assertIn("baseline.py", Path(snapshots["diff_before"]).read_text())
            self.assertIn("sample.py", Path(snapshots["diff_after"]).read_text())
            self.assertIn("sample.py", Path(snapshots["attempt_delta"]).read_text())
            prompt = latest_run_file(root, "fix", "DSL-000001", "prompt.txt").read_text()
            self.assertIn("You are running as the selected Ultimate De-Slop fixer role", prompt)
            self.assertIn("finding_id, summary, changed_files, checks_run, risks, status", prompt)
            self.assertNotIn("If a deslop_fixer profile or subagent is available", prompt)

    def test_verify_prompt_uses_per_finding_attempt_snapshot(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            fix_dir = root / ".deslop" / "runs" / "20260531T000000Z-fix-DSL-000001"
            fix_dir.mkdir(parents=True)
            status_before = fix_dir / "git-status-before.txt"
            diff_before = fix_dir / "git-diff-before.patch"
            status_after = fix_dir / "git-status-after.txt"
            diff_after = fix_dir / "git-diff-after.patch"
            attempt_delta = fix_dir / "git-diff-attempt.patch"
            status_before.write_text(" M baseline.py\n")
            diff_before.write_text("diff --git a/baseline.py b/baseline.py\n")
            status_after.write_text(" M baseline.py\n M sample.py\n")
            diff_after.write_text("diff --git a/sample.py b/sample.py\n+value = 2\n")
            attempt_delta.write_text("+diff --git a/sample.py b/sample.py\n++value = 2\n")
            finding = minimal_finding("DSL-000001", files=["sample.py"])
            finding["status"] = "fixed_unverified"
            finding["last_fix"] = {
                "snapshot_paths": {
                    "status_before": str(status_before),
                    "diff_before": str(diff_before),
                    "status_after": str(status_after),
                    "diff_after": str(diff_after),
                    "attempt_delta": str(attempt_delta),
                }
            }
            write_findings(root, finding)

            checks_dir = root / ".deslop" / "runs" / "20260531T000100Z-checks-DSL-000001"
            checks_dir.mkdir()
            checks_path = checks_dir / "checks.json"
            checks_path.write_text(
                json.dumps({"finding_id": "DSL-000001", "status": "passed", "results": []}) + "\n"
            )

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            fake_codex = fake_bin / "codex"
            fake_codex.write_text(
                """#!/usr/bin/env python3
import json
import sys
from pathlib import Path

payload = {
    "finding_id": "DSL-0000001",
    "verdict": "PASS",
    "confidence": "high",
    "evidence": "checked attempt delta",
    "concerns": "None",
    "required_follow_up": "None",
}
text = json.dumps(payload)
if "--output-last-message" in sys.argv:
    Path(sys.argv[sys.argv.index("--output-last-message") + 1]).write_text(text + "\\n")
print(text)
"""
            )
            fake_codex.chmod(0o755)

            result = run(
                [str(SCRIPT_DIR / "deslop-verify.sh"), "--checks-json", str(checks_path), "DSL-000001"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            verify = json.loads(latest_run_file(root, "verify", "DSL-000001", "verify.json").read_text())
            self.assertEqual(verify["finding_id"], "DSL-000001")
            self.assertEqual(verify["confidence"], 0.95)
            self.assertEqual(verify["evidence"], ["checked attempt delta"])
            self.assertEqual(verify["concerns"], [])
            self.assertEqual(verify["required_follow_up"], [])
            prompt = latest_run_file(root, "verify", "DSL-000001", "prompt.txt").read_text()
            self.assertIn("Per-finding fix attempt context", prompt)
            self.assertIn("Patch-of-patches for changes introduced during this fix attempt", prompt)
            self.assertIn("do not fail solely because unrelated baseline changes are present", prompt)
            self.assertIn("sample.py", prompt)
            self.assertIn("You are running as the selected Ultimate De-Slop verifier role", prompt)
            self.assertIn("finding_id, verdict, confidence, evidence, concerns, required_follow_up", prompt)
            self.assertNotIn("Use deslop_verifier if available", prompt)

    def test_verify_rejects_needs_human_without_concerns_or_follow_up(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            checks_path = prepare_verify_fixture(root)
            fake_bin = root / "fake-bin"
            write_fake_codex_verify(
                fake_bin,
                {
                    "finding_id": "DSL-000001",
                    "verdict": "NEEDS_HUMAN",
                    "confidence": 0.9,
                    "evidence": ["patch touches auth boundary"],
                    "concerns": [],
                    "required_follow_up": [],
                },
            )

            result = run(
                [str(SCRIPT_DIR / "deslop-verify.sh"), "--checks-json", str(checks_path), "DSL-000001"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("NEEDS_HUMAN", result.stderr)
            self.assertRegex(result.stderr, r"concerns|required_follow_up")

    def test_verify_rejects_empty_evidence(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            checks_path = prepare_verify_fixture(root)
            fake_bin = root / "fake-bin"
            write_fake_codex_verify(
                fake_bin,
                {
                    "finding_id": "DSL-000001",
                    "verdict": "PASS",
                    "confidence": 0.9,
                    "evidence": [],
                    "concerns": [],
                    "required_follow_up": [],
                },
            )

            result = run(
                [str(SCRIPT_DIR / "deslop-verify.sh"), "--checks-json", str(checks_path), "DSL-000001"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("evidence", result.stderr)

    def test_verify_accepts_false_positive_with_evidence(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            checks_path = prepare_verify_fixture(root)
            fake_bin = root / "fake-bin"
            write_fake_codex_verify(
                fake_bin,
                {
                    "finding_id": "DSL-000001",
                    "verdict": "FALSE_POSITIVE",
                    "confidence": 0.92,
                    "evidence": ["The duplicated helpers already share validate_request()."],
                    "concerns": [],
                    "required_follow_up": [],
                },
            )

            result = run(
                [str(SCRIPT_DIR / "deslop-verify.sh"), "--checks-json", str(checks_path), "DSL-000001"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            verify = json.loads(latest_run_file(root, "verify", "DSL-000001", "verify.json").read_text())
            self.assertEqual(verify["verdict"], "FALSE_POSITIVE")
            self.assertEqual(
                verify["evidence"],
                ["The duplicated helpers already share validate_request()."],
            )

    def test_finalize_prints_needs_human_reasons(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            finding = minimal_finding("DSL-000001")
            finding["status"] = "fixed_unverified"
            write_findings(root, finding)
            verify_dir = root / ".deslop" / "runs" / "20260531T000200Z-verify-DSL-000001"
            verify_dir.mkdir(parents=True)
            verify_path = verify_dir / "verify.json"
            verify_path.write_text(
                json.dumps(
                    {
                        "finding_id": "DSL-000001",
                        "verdict": "NEEDS_HUMAN",
                        "confidence": 0.88,
                        "evidence": ["Auth boundary changed"],
                        "concerns": ["Unclear whether session invalidation is intentional"],
                        "required_follow_up": ["Confirm logout semantics with product"],
                    }
                )
                + "\n"
            )
            checks_dir = root / ".deslop" / "runs" / "20260531T000100Z-checks-DSL-000001"
            checks_dir.mkdir(parents=True)
            checks_path = checks_dir / "checks.json"
            checks_path.write_text(
                json.dumps({"finding_id": "DSL-000001", "status": "passed", "results": []}) + "\n"
            )

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-finalize.py"),
                    "DSL-000001",
                    "--verify-json",
                    str(verify_path),
                    "--checks-json",
                    str(checks_path),
                ],
                cwd=root,
            )

            self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
            self.assertIn("needs_human", result.stdout)
            self.assertIn("Unclear whether session invalidation is intentional", result.stdout)
            self.assertIn("Confirm logout semantics with product", result.stdout)
            self.assertEqual(read_finding(root, "DSL-000001")["status"], "needs_human")

    def test_finalize_prints_false_positive_evidence(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            finding = minimal_finding("DSL-000001")
            finding["status"] = "fixed_unverified"
            write_findings(root, finding)
            verify_dir = root / ".deslop" / "runs" / "20260531T000200Z-verify-DSL-000001"
            verify_dir.mkdir(parents=True)
            verify_path = verify_dir / "verify.json"
            verify_path.write_text(
                json.dumps(
                    {
                        "finding_id": "DSL-000001",
                        "verdict": "FALSE_POSITIVE",
                        "confidence": 0.91,
                        "evidence": ["Helpers already share one validator"],
                        "concerns": [],
                        "required_follow_up": [],
                    }
                )
                + "\n"
            )
            checks_dir = root / ".deslop" / "runs" / "20260531T000100Z-checks-DSL-000001"
            checks_dir.mkdir(parents=True)
            checks_path = checks_dir / "checks.json"
            checks_path.write_text(
                json.dumps({"finding_id": "DSL-000001", "status": "passed", "results": []}) + "\n"
            )

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-finalize.py"),
                    "DSL-000001",
                    "--verify-json",
                    str(verify_path),
                    "--checks-json",
                    str(checks_path),
                ],
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("false_positive", result.stdout)
            self.assertIn("Helpers already share one validator", result.stdout)
            self.assertEqual(read_finding(root, "DSL-000001")["status"], "false_positive")

    def test_record_outcome_writes_loop_outcome(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            run([str(SCRIPT_DIR / "deslop-init.sh")], cwd=root, check=True)
            verified = minimal_finding("DSL-000001")
            verified["status"] = "verified"
            verified["title"] = "Share request validation"
            needs = minimal_finding("DSL-000002")
            needs["status"] = "needs_human"
            needs["title"] = "Auth rewrite needs review"
            needs["verification"] = {
                "concerns": ["Ambiguous logout semantics"],
                "required_follow_up": ["Ask product"],
                "evidence": ["Touches session store"],
            }
            false_pos = minimal_finding("DSL-000003")
            false_pos["status"] = "false_positive"
            false_pos["title"] = "Speculative unused helper"
            false_pos["verification"] = {"evidence": ["Helper is used by import path"]}
            queued = minimal_finding("DSL-000004")
            queued["status"] = "accepted"
            queued["title"] = "Queued cleanup"
            write_findings(root, verified, needs, false_pos, queued)

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-record-outcome.py"),
                    "--stop-reason",
                    "finalize_halt",
                    "--max-iterations",
                    "5",
                    "--priority",
                    "P0,P1",
                    "--iterations-completed",
                    "1",
                    "--halt-finding-id",
                    "DSL-000002",
                    "--halt-status",
                    "needs_human",
                    "--baseline-verified-ids",
                    "",
                ],
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            state = json.loads((root / ".deslop" / "state.json").read_text())
            outcome = state["loop_outcome"]
            self.assertEqual(outcome["stop_reason"], "finalize_halt")
            self.assertEqual(outcome["verified_ids"], ["DSL-000001"])
            self.assertEqual(outcome["halt_finding_id"], "DSL-000002")
            self.assertEqual(outcome["halt_status"], "needs_human")
            self.assertEqual(state["stop"]["reason"], "finalize_halt")

    def test_status_includes_loop_summary(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            run([str(SCRIPT_DIR / "deslop-init.sh")], cwd=root, check=True)
            verified = minimal_finding("DSL-000001")
            verified["status"] = "verified"
            verified["title"] = "Share request validation"
            needs = minimal_finding("DSL-000002")
            needs["status"] = "needs_human"
            needs["title"] = "Auth rewrite needs review"
            needs["verification"] = {
                "concerns": ["Ambiguous logout semantics"],
                "required_follow_up": ["Ask product"],
                "evidence": ["Touches session store"],
            }
            false_pos = minimal_finding("DSL-000003")
            false_pos["status"] = "false_positive"
            false_pos["title"] = "Speculative unused helper"
            false_pos["verification"] = {"evidence": ["Helper is used by import path"]}
            write_findings(root, verified, needs, false_pos)
            run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-record-outcome.py"),
                    "--stop-reason",
                    "no_eligible_findings",
                    "--max-iterations",
                    "5",
                    "--priority",
                    "P0,P1",
                    "--iterations-completed",
                    "2",
                    "--baseline-verified-ids",
                    "",
                ],
                cwd=root,
                check=True,
            )

            result = run([sys.executable, str(SCRIPT_DIR / "deslop-status.py"), "--json"], cwd=root)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            status = json.loads(result.stdout)
            summary = status["loop_summary"]
            self.assertEqual(summary["stop_reason"], "no_eligible_findings")
            self.assertEqual(summary["verified"], [{"id": "DSL-000001", "title": "Share request validation"}])
            self.assertEqual(summary["needs_human"][0]["id"], "DSL-000002")
            self.assertIn("Ambiguous logout semantics", summary["needs_human"][0]["details"])
            self.assertEqual(summary["false_positives"][0]["id"], "DSL-000003")

            text = run([sys.executable, str(SCRIPT_DIR / "deslop-status.py")], cwd=root)
            self.assertEqual(text.returncode, 0, text.stderr + text.stdout)
            self.assertIn("Loop outcome", text.stdout)
            self.assertIn("no_eligible_findings", text.stdout)
            self.assertIn("DSL-000001", text.stdout)
            self.assertIn("Needs human", text.stdout)
            self.assertIn("Ambiguous logout semantics", text.stdout)

    def test_loop_records_no_eligible_findings_outcome(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("value = 1\n")
            (root / ".gitignore").write_text(".deslop/\nfake-bin/\n")
            run(["git", "add", "sample.py", ".gitignore"], cwd=root, check=True)
            run(["git", "commit", "-m", "sample"], cwd=root, check=True)
            run([str(SCRIPT_DIR / "deslop-init.sh")], cwd=root, check=True)
            write_findings(root)

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "codex",
                """#!/usr/bin/env bash
set -euo pipefail
last=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    last="$2"
    shift 2
    continue
  fi
  shift
done
payload='{"repo_summary":"empty","review_wave_id":"wave-1","partitions_reviewed":["all"],"findings":[]}'
if [ -n "$last" ]; then
  printf '%s\\n' "$payload" > "$last"
fi
printf '%s\\n' "$payload"
""",
            )

            result = run(
                [str(SCRIPT_DIR / "deslop-loop.sh"), "--max-iterations", "1", "--priority", "P0,P1"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}", "DESLOP_HARNESS": "codex"},
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            state = json.loads((root / ".deslop" / "state.json").read_text())
            self.assertEqual(state["loop_outcome"]["stop_reason"], "no_eligible_findings")
            self.assertIn("no_eligible_findings", result.stdout)
            self.assertIn("Loop outcome", result.stdout)

    def test_deterministic_proof_run(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "app.py").write_text(
                """def create(payload):
    if not payload.get("name"):
        raise ValueError("name required")
    if not payload.get("email"):
        raise ValueError("email required")
    return payload


def update(payload):
    if not payload.get("name"):
        raise ValueError("name required")
    if not payload.get("email"):
        raise ValueError("email required")
    return payload
"""
            )
            (root / ".gitignore").write_text(".deslop/\nfake-bin/\n")
            run(["git", "add", "app.py", ".gitignore"], cwd=root, check=True)
            run(["git", "commit", "-m", "duplicate validation"], cwd=root, check=True)

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "codex",
                r"""#!/usr/bin/env python3
import json
import sys
from pathlib import Path

argv = sys.argv[1:]
schema = ""
last = ""
root = Path.cwd()
idx = 0
while idx < len(argv):
    arg = argv[idx]
    if arg == "--output-schema":
        schema = argv[idx + 1]
        idx += 2
        continue
    if arg == "--output-last-message":
        last = argv[idx + 1]
        idx += 2
        continue
    if arg == "--cd":
        root = Path(argv[idx + 1])
        idx += 2
        continue
    idx += 1

prompt = sys.stdin.read()
schema_name = Path(schema).name if schema else ""
state_path = root / ".deslop" / "proof-fake-state.json"
state = {"reviews": 0}
if state_path.exists():
    state = json.loads(state_path.read_text())

if schema_name == "review.schema.json":
    state["reviews"] = int(state.get("reviews", 0)) + 1
    if state["reviews"] == 1:
        payload = {
            "repo_summary": "small python app with duplicated validation",
            "review_wave_id": "wave-proof-1",
            "partitions_reviewed": ["."],
            "findings": [
                {
                    "id": "candidate-1",
                    "title": "Request validation is duplicated across create and update",
                    "severity": "P1",
                    "confidence": 0.91,
                    "category": "boundary-abstraction",
                    "status": "candidate",
                    "files": ["app.py"],
                    "evidence": [
                        {
                            "file": "app.py",
                            "lines": "1-20",
                            "symbol": "create",
                            "claim": "create() and update() both repeat `if not payload.get(\"name\")` and email checks.",
                        }
                    ],
                    "why_it_matters": "Divergent validation can produce inconsistent writes.",
                    "proposed_fix": "Extract shared validate_payload() and call it from create and update.",
                    "acceptance_criteria": ["create and update call one shared validator"],
                    "expected_checks": ["python3 -m py_compile app.py"],
                    "expected_checks_explanation": "",
                    "no_expected_checks_reason": "",
                    "checks_explanation": "",
                    "risk": "low",
                    "dependencies": [],
                    "estimated_effort": "small",
                    "reviewer": "deslop-reviewer",
                    "created_at": "2026-07-08T00:00:00Z",
                    "updated_at": "2026-07-08T00:00:00Z",
                }
            ],
        }
    else:
        payload = {
            "repo_summary": "validation already shared",
            "review_wave_id": "wave-proof-2",
            "partitions_reviewed": ["."],
            "findings": [],
        }
elif schema_name == "fix.schema.json":
    app = root / "app.py"
    app.write_text(
        "def validate_payload(payload):\n"
        "    if not payload.get(\"name\"):\n"
        "        raise ValueError(\"name required\")\n"
        "    if not payload.get(\"email\"):\n"
        "        raise ValueError(\"email required\")\n"
        "    return payload\n"
        "\n"
        "\n"
        "def create(payload):\n"
        "    return validate_payload(payload)\n"
        "\n"
        "\n"
        "def update(payload):\n"
        "    return validate_payload(payload)\n"
    )
    payload = {
        "finding_id": "DSL-000001",
        "summary": "Extracted shared validate_payload helper",
        "changed_files": ["app.py"],
        "checks_run": ["python3 -m py_compile app.py"],
        "risks": ["low"],
        "status": "fixed",
    }
elif schema_name == "verify.schema.json":
    payload = {
        "finding_id": "DSL-000001",
        "verdict": "PASS",
        "confidence": 0.93,
        "evidence": ["create and update both call validate_payload()"],
        "concerns": [],
        "required_follow_up": [],
    }
else:
    raise SystemExit(f"unexpected schema: {schema_name or schema}")

state_path.parent.mkdir(parents=True, exist_ok=True)
state_path.write_text(json.dumps(state) + "\n")
text = json.dumps(payload)
if last:
    Path(last).write_text(text + "\n")
print(text)
""",
            )

            result = run(
                [str(SCRIPT_DIR / "deslop-loop.sh"), "--max-iterations", "2", "--priority", "P0,P1"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}", "DESLOP_HARNESS": "codex"},
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            finding = read_finding(root, "DSL-000001")
            self.assertEqual(finding["status"], "verified")
            self.assertIn("validate_payload", (root / "app.py").read_text())
            state = json.loads((root / ".deslop" / "state.json").read_text())
            outcome = state["loop_outcome"]
            self.assertEqual(outcome["stop_reason"], "no_eligible_findings")
            self.assertEqual(outcome["verified_ids"], ["DSL-000001"])
            self.assertTrue(list((root / ".deslop" / "runs").glob("*-review/review.json")))
            self.assertTrue(list((root / ".deslop" / "runs").glob("*-fix-DSL-000001/fix.json")))
            self.assertTrue(list((root / ".deslop" / "runs").glob("*-verify-DSL-000001/verify.json")))
            self.assertIn("Loop outcome", result.stdout)
            self.assertIn("DSL-000001", result.stdout)
            self.assertIn("no_eligible_findings", result.stdout)

    def test_doctor_reports_missing_cli(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            empty_bin = root / "empty-bin"
            empty_bin.mkdir()
            result = run(
                [sys.executable, str(SCRIPT_DIR / "deslop-doctor.py"), "--json", "--harness", "codex"],
                cwd=root,
                env={"PATH": str(empty_bin), "DESLOP_HARNESS": "codex"},
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            report = json.loads(result.stdout)
            self.assertFalse(report["ready"])
            codes = {item["code"]: item for item in report["checks"]}
            self.assertFalse(codes["cli_on_path"]["ok"])

    def test_doctor_requires_cursor_auth(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(fake_bin / "cursor-agent", "#!/usr/bin/env bash\nexit 0\n")
            env = {
                "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
                "DESLOP_HARNESS": "cursor",
            }
            env.pop("CURSOR_API_KEY", None)
            env.pop("CURSOR_AUTH_TOKEN", None)
            # scrub inherited auth
            clean = {k: v for k, v in os.environ.items() if k not in {"CURSOR_API_KEY", "CURSOR_AUTH_TOKEN"}}
            clean.update(env)
            result = run(
                [sys.executable, str(SCRIPT_DIR / "deslop-doctor.py"), "--json", "--harness", "cursor"],
                cwd=root,
                env=clean,
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            report = json.loads(result.stdout)
            codes = {item["code"]: item for item in report["checks"]}
            self.assertTrue(codes["cli_on_path"]["ok"])
            self.assertFalse(codes["auth_env"]["ok"])

    def test_doctor_ready_when_cli_present(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            run([str(SCRIPT_DIR / "deslop-init.sh")], cwd=root, check=True)
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(fake_bin / "codex", "#!/usr/bin/env bash\nexit 0\n")
            result = run(
                [sys.executable, str(SCRIPT_DIR / "deslop-doctor.py"), "--json", "--harness", "codex"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}", "DESLOP_HARNESS": "codex"},
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads(result.stdout)
            self.assertTrue(report["ready"])

    def test_verify_rejects_pass_without_test_file_changes(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            checks_path = prepare_verify_fixture(root)
            finding = read_finding(root, "DSL-000001")
            finding["expected_checks"] = ["python3 -m unittest discover -s tests -v"]
            finding["acceptance_criteria"] = ["add a regression test for the shared validator"]
            finding["last_fix"] = {
                **(finding.get("last_fix") or {}),
                "changed_files": ["sample.py"],
            }
            write_findings(root, finding)
            fake_bin = root / "fake-bin"
            write_fake_codex_verify(
                fake_bin,
                {
                    "finding_id": "DSL-000001",
                    "verdict": "PASS",
                    "confidence": 0.9,
                    "evidence": ["validator is shared"],
                    "concerns": [],
                    "required_follow_up": [],
                },
            )

            result = run(
                [str(SCRIPT_DIR / "deslop-verify.sh"), "--checks-json", str(checks_path), "DSL-000001"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("behavioral coverage", result.stderr)
            self.assertIn("test", result.stderr.lower())

    def test_status_priority_note_when_p2_remain(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            run([str(SCRIPT_DIR / "deslop-init.sh")], cwd=root, check=True)
            verified = minimal_finding("DSL-000001")
            verified["status"] = "verified"
            p2 = minimal_finding("DSL-000004")
            p2["severity"] = "P2"
            p2["status"] = "accepted"
            p2["title"] = "Queued P2 cleanup"
            write_findings(root, verified, p2)
            run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-record-outcome.py"),
                    "--stop-reason",
                    "no_eligible_findings",
                    "--max-iterations",
                    "5",
                    "--priority",
                    "P0,P1",
                    "--iterations-completed",
                    "2",
                    "--baseline-verified-ids",
                    "",
                ],
                cwd=root,
                check=True,
            )

            result = run([sys.executable, str(SCRIPT_DIR / "deslop-status.py"), "--json"], cwd=root)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            status = json.loads(result.stdout)
            self.assertIsNone(status["next"])
            self.assertIn("P2 remain", status["loop_summary"]["priority_note"])
            self.assertTrue(any("P0,P1,P2" in command for command in status["suggested_commands"]))

            text = run([sys.executable, str(SCRIPT_DIR / "deslop-status.py")], cwd=root)
            self.assertIn("Priority note", text.stdout)
            self.assertIn("P2 remain", text.stdout)

    def test_fix_marks_needs_human_when_change_budget_exceeded(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            (root / "sample.py").write_text("value = 1\n")
            (root / "extra.py").write_text("other = 1\n")
            run(["git", "add", "sample.py", "extra.py"], cwd=root, check=True)
            run(["git", "commit", "-m", "base"], cwd=root, check=True)
            config = json.loads((root / ".deslop" / "config.json").read_text())
            config["max_changed_files_per_fix"] = 1
            config["max_changed_lines_per_fix"] = 400
            (root / ".deslop" / "config.json").write_text(json.dumps(config) + "\n")
            write_findings(root, minimal_finding("DSL-000001", files=["sample.py", "extra.py"]))

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            write_executable(
                fake_bin / "codex",
                """#!/usr/bin/env python3
import json
import sys
from pathlib import Path
root = Path.cwd()
(root / "sample.py").write_text("value = 2\\n")
(root / "extra.py").write_text("other = 2\\n")
payload = {
    "finding_id": "DSL-000001",
    "summary": "touched two files",
    "changed_files": ["sample.py", "extra.py"],
    "checks_run": [],
    "risks": [],
    "status": "fixed",
}
text = json.dumps(payload)
if "--output-last-message" in sys.argv:
    Path(sys.argv[sys.argv.index("--output-last-message") + 1]).write_text(text + "\\n")
print(text)
""",
            )

            result = run(
                [str(SCRIPT_DIR / "deslop-fix.sh"), "--allow-dirty", "DSL-000001"],
                cwd=root,
                env={"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"},
            )

            self.assertNotEqual(result.returncode, 0, result.stdout)
            finding = read_finding(root, "DSL-000001")
            self.assertEqual(finding["status"], "needs_human")
            self.assertIn("change budget", str(finding.get("block_reason", "")))

    def test_resume_moves_needs_human_to_accepted(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            run([str(SCRIPT_DIR / "deslop-init.sh")], cwd=root, check=True)
            finding = minimal_finding("DSL-000003")
            finding["status"] = "needs_human"
            finding["block_reason"] = "needs judgment"
            write_findings(root, finding)

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-resume.py"),
                    "DSL-000003",
                    "--as",
                    "accepted",
                    "--reason",
                    "human approved retry",
                ],
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            updated = read_finding(root, "DSL-000003")
            self.assertEqual(updated["status"], "accepted")
            self.assertEqual(updated["resume"]["from_status"], "needs_human")
            self.assertNotIn("block_reason", updated)

    def test_resume_rejects_verified_source(self) -> None:
        tempdir, root = self.make_repo()
        with tempdir:
            run([str(SCRIPT_DIR / "deslop-init.sh")], cwd=root, check=True)
            finding = minimal_finding("DSL-000001")
            finding["status"] = "verified"
            write_findings(root, finding)

            result = run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "deslop-resume.py"),
                    "DSL-000001",
                    "--as",
                    "accepted",
                ],
                cwd=root,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("cannot resume", result.stderr)


if __name__ == "__main__":
    unittest.main()
