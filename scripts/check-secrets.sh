#!/usr/bin/env bash
# Redacted repository leak check for tracked and non-ignored local files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import os
import re
import subprocess
import sys

raw = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
    text=False,
)
files = [f.decode("utf-8", "replace") for f in raw.split(b"\0") if f]

skip_prefixes = (
    "third_party/",
)
skip_suffixes = (
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".pdf",
    ".dmg",
    ".pkg",
    ".zip",
    ".a",
    ".o",
    ".dylib",
    ".so",
    ".swiftmodule",
    ".swiftdoc",
    ".xcuserstate",
)

secret_filename = re.compile(
    r"(^|/)(AuthKey_[A-Z0-9]+\.p8|.*\.(p8|p12|key|pem|mobileprovision|provisionprofile))$",
    re.IGNORECASE,
)

patterns = [
    ("private-key-block", re.compile(r"-----BEGIN (?:RSA |DSA |EC |OPENSSH |)?PRIVATE KEY-----")),
    ("github-token", re.compile(r"(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}")),
    ("openai-key", re.compile(r"sk-[A-Za-z0-9]{20,}")),
    ("aws-access-key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("google-api-key", re.compile(r"AIza[0-9A-Za-z_-]{35}")),
    ("slack-token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("bearer-token", re.compile(r"(?i)\bAuthorization:\s*Bearer\s+[A-Za-z0-9._-]{16,}")),
    ("hardcoded-notary-key-id", re.compile(r"NOTARY_KEY_ID:-[A-Z0-9]{8,}")),
    ("hardcoded-notary-issuer", re.compile(r"NOTARY_ISSUER_ID:-[0-9a-fA-F-]{32,}")),
    ("hardcoded-developer-id", re.compile(r"Developer ID (?:Application|Installer): [^\"'<$][^\n]*\([A-Z0-9]{10}\)")),
]

hits = []

for path in files:
    if path.startswith(skip_prefixes) or path.endswith(skip_suffixes):
        continue
    if secret_filename.search(path):
        hits.append((path, 0, "secret-like-filename"))
        continue
    try:
        with open(path, "rb") as handle:
            data = handle.read(2_000_000)
    except OSError:
        continue
    if b"\0" in data[:4096]:
        continue
    text = data.decode("utf-8", "replace")
    for line_no, line in enumerate(text.splitlines(), 1):
        for name, regex in patterns:
            if regex.search(line):
                hits.append((path, line_no, name))

if hits:
    print("Potential secret material found. Values are redacted; inspect the listed locations.")
    for path, line_no, name in hits:
        loc = f"{path}:{line_no}" if line_no else path
        print(f"- {loc} [{name}]")
    sys.exit(1)

print(f"check-secrets: OK ({len(files)} tracked/non-ignored files scanned)")
PY
