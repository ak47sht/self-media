#!/usr/bin/env python3
"""Fail if public repo files contain obvious secrets or private deployment paths."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOWLIST = {
    "scripts/public_safety_check.py",
}
PATTERNS = [
    ("github token", re.compile(r"(?:ghp|github_pat)_[A-Za-z0-9_]{20,}")),
    ("private deployment path", re.compile(r"/(?:opt/(?:movie-lite|music-lite|agent-ops-dashboard)|root/\.hermes|root/openclaw)", re.I)),
    ("private relay token-looking URL credential", re.compile(r"https://[^\s/@]+:[^\s/@]+@")),
]

tracked = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).splitlines()
failures: list[str] = []
for rel in tracked:
    if rel in ALLOWLIST:
        continue
    path = ROOT / rel
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    for label, pattern in PATTERNS:
        if pattern.search(text):
            failures.append(f"{rel}: {label}")

if failures:
    print("PUBLIC SAFETY CHECK FAILED")
    for item in failures:
        print("-", item)
    raise SystemExit(1)
print(f"public safety ok: scanned {len(tracked)} tracked files")
