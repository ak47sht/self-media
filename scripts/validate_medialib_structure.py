#!/usr/bin/env python3
"""Structural validator for the MediaLib (rebased) macOS app.

Runs on the Linux CI host where no Swift toolchain is available. It does not
compile; it asserts that the key architectural pieces are present and wired so
that a broken refactor is caught before the macOS build job runs.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAILURES: list[str] = []


def must_exist(rel: str) -> None:
    if not (ROOT / rel).exists():
        FAILURES.append(f"missing file: {rel}")


def must_contain(rel: str, needles: list[str]) -> None:
    path = ROOT / rel
    if not path.is_file():
        FAILURES.append(f"missing file: {rel}")
        return
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            FAILURES.append(f"{rel}: missing {needle!r}")


# --- Package manifest defines the three rebased targets ---
must_contain(
    "Package.swift",
    [
        'name: "MediaLibCore"',
        'name: "MediaLib"',
        'name: "MediaLibChecks"',
        ".macOS(.v13)",
    ],
)

# --- Core layering present ---
must_exist("Sources/MediaLibCore/Database/DatabaseManager.swift")
must_exist("Sources/MediaLibCore/Models/MediaSource.swift")
must_exist("Sources/MediaLibCore/Services/MediaScanner.swift")

# --- App entry + libmpv player + remote connectors present ---
must_exist("Sources/MediaLib/App/MediaLibApp.swift")
must_contain(
    "Sources/MediaLib/App/LibMpvClient.swift",
    ["libmpv.2.dylib", "dlopen"],
)
must_exist("Sources/MediaLib/App/EmbyService.swift")
must_exist("Sources/MediaLib/App/PlexService.swift")

# --- Build tooling carried over ---
must_exist("scripts/medialib/package_dmg.sh")
must_exist("scripts/medialib/generate_icon.swift")

if FAILURES:
    print("MEDIALIB STRUCTURE CHECK FAILED")
    for item in FAILURES:
        print("-", item)
    raise SystemExit(1)
print("medialib structure ok")
