#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def assert_contains(path: str, needles: list[str]) -> None:
    text = (ROOT / path).read_text()
    missing = [needle for needle in needles if needle not in text]
    assert not missing, f"{path} missing: {missing}"


def test_source_models_exist() -> None:
    assert_contains(
        "Sources/OpenClawMedia/SourceConfig.swift",
        [
            "enum MediaSourceKind",
            "case backendMovie",
            "case backendMusic",
            "case iptvM3U",
            "case aiImageProvider",
            "struct MediaSourceConfig",
            "struct SourceCapability",
            "defaultSources",
        ],
    )


def test_settings_ui_exposes_sources() -> None:
    assert_contains(
        "Sources/OpenClawMedia/App.swift",
        [
            "@State private var sidebarSelection",
            "case settings = \"Settings\"",
            "SourcesSettingsView",
            "Direct play locally",
            "Backend normalized",
            "External player ready",
        ],
    )


def test_docs_are_linked() -> None:
    assert_contains(
        "README.md",
        [
            "docs/CONFIGURABLE_SOURCES.md",
            "docs/MEDIA_APP_REFERENCES.md",
            "docs/FIGMA_BRIEF.md",
            "docs/FIGMA_MAKE_PROMPT.md",
            "docs/FIGMA_MAKE_EXPORT_ANALYSIS.md",
        ],
    )


if __name__ == "__main__":
    tests = [test_source_models_exist, test_settings_ui_exposes_sources, test_docs_are_linked]
    for test in tests:
        test()
        print(f"ok {test.__name__}")
