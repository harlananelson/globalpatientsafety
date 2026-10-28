#!/usr/bin/env python3
"""Shim: pack the Global Patient Safety Copilot knowledge with copilot-pack.

The machinery is the copilot-pack package; what to pack is declared in copilot/pack.yaml here.
Flags pass through: --dry-run, --max-tokens, --max-files.

    python tools/pack_copilot_knowledge.py [--dry-run]

Install copilot-pack first (a private package; install it from your own copy).
The built output (copilot/knowledge/) is gitignored. The previous 489-line packer was never committed;
its document list is now copilot/pack.yaml.
"""
import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

if shutil.which("copilot-pack"):
    cmd = ["copilot-pack"]
elif importlib.util.find_spec("copilot_pack"):
    cmd = [sys.executable, "-m", "copilot_pack"]
else:
    sys.exit("copilot-pack is not installed. Install the copilot-pack package, then re-run.")
sys.exit(subprocess.call([*cmd, "--project", str(ROOT), *sys.argv[1:]]))
