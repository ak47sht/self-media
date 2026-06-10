#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "Sources/OpenClawMedia/App.swift"


def test_figma_v02_visual_tokens() -> None:
    text = APP.read_text()
    required = [
        "#0B0D10",
        "#14171D",
        "#1B1F27",
        "#0A84FF",
        "#30D158",
        "#FFD60A",
        "static let sidebarWidth: CGFloat = 240",
        "static let detailPanelWidth: CGFloat = 320",
        "static let sidebarRadius: CGFloat = 20",
        "static let rowRadius: CGFloat = 14",
        "static let gap8: CGFloat = 8",
        "static let gap12: CGFloat = 12",
        "static let gap16: CGFloat = 16",
        "static let purple = blue",
    ]
    missing = [needle for needle in required if needle not in text]
    assert not missing, f"Figma v0.2 visual token drift: {missing}"


def test_figma_shell_landmarks() -> None:
    text = APP.read_text()
    required = [
        "OpenClaw Media",
        "Personal cockpit",
        "SidebarSectionTitle(\"MEDIA\")",
        "QuickSearchRow()",
        "FilterChip(title: \"News\")",
        "nowPlayingHost",
        "RouteDisplay.hostSummary",
        "playback.isPlaying ? AppTheme.green",
        "RoundedRectangle(cornerRadius: DesignTokens.panelRadius",
        "RoundedRectangle(cornerRadius: DesignTokens.rowRadius",
    ]
    missing = [needle for needle in required if needle not in text]
    assert not missing, f"Figma shell landmark drift: {missing}"


if __name__ == "__main__":
    test_figma_v02_visual_tokens()
    print("ok test_figma_v02_visual_tokens")
    test_figma_shell_landmarks()
    print("ok test_figma_shell_landmarks")
