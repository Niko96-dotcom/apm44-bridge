#!/usr/bin/env python3
"""Backward-compatible Codex adapter shim for the neutral de-slop runner."""

from __future__ import annotations

import os
import runpy
from pathlib import Path


os.environ["DESLOP_HARNESS"] = "codex"
runpy.run_path(str(Path(__file__).with_name("deslop-agent-runner.py")), run_name="__main__")
