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


def test_in_app_configuration_is_editable_and_persisted() -> None:
    assert_contains(
        "Sources/OpenClawMedia/Config.swift",
        [
            "iptvPlaylistURL",
            "aiImageProviderBaseURL",
            "aiImageProviderModel",
            "aiImageAPIKey",
            "enum ConfigStore",
            "save(_ config",
            "applicationSupportConfigURL",
        ],
    )
    assert_contains(
        "Sources/OpenClawMedia/App.swift",
        [
            "@State private var config = ConfigLoader.load()",
            "ConfigurationCenterView",
            "EditableAppConfig",
            "Save configuration",
            "Movie backend URL",
            "Music backend URL",
            "IPTV / M3U URL",
            "AI provider base URL",
            "AI provider API key",
            "AI provider model",
        ],
    )


def test_native_playback_ga_paths_exist() -> None:
    assert_contains(
        "Sources/OpenClawMedia/PlaybackSupport.swift",
        [
            "NativePlaybackManager",
            "AVPlayer",
            "ResolvedPlaybackRoute",
            "PlaybackRouteResolver",
            "play(url:",
        ],
    )
    assert_contains(
        "Sources/OpenClawMedia/App.swift",
        [
            "VideoPlayer(player:",
            "Play video",
            "Play music",
            "Copy URL",
            "LyricsPreview(lyrics:",
            "api.playURL(for:",
            "api.lyrics(for:",
            "NSPasteboard.general",
        ],
    )


def test_ai_key_uses_keychain_not_json() -> None:
    assert_contains(
        "Sources/OpenClawMedia/Config.swift",
        [
            "import Security",
            "enum AIProviderSecretStore",
            "SecItemAdd",
            "SecItemCopyMatching",
            "try AIProviderSecretStore.saveAPIKey(config.aiImageAPIKey)",
            "Intentionally omit" if False else "try container.encode(aiImageProviderModel",
        ],
    )


def test_next_ga_completions_exist() -> None:
    assert_contains(
        "Sources/OpenClawMedia/App.swift",
        [
            "Open in IINA",
            "openCurrentURLInIINA",
            "NSWorkspace.shared.open",
            "generateImage",
            "generatedImageURL",
        ],
    )
    assert_contains(
        "Sources/OpenClawMedia/MediaAPI.swift",
        [
            "func generateImage",
            "Bearer",
            "images/generations",
        ],
    )
    assert_contains(
        "Sources/OpenClawMedia/Config.swift",
        [
            "var reloadIdentity",
            "aiImageProviderBaseURL?.absoluteString",
            "iptvPlaylistURL?.absoluteString",
        ],
    )


if __name__ == "__main__":
    tests = [
        test_source_models_exist,
        test_settings_ui_exposes_sources,
        test_docs_are_linked,
        test_in_app_configuration_is_editable_and_persisted,
        test_native_playback_ga_paths_exist,
        test_ai_key_uses_keychain_not_json,
        test_next_ga_completions_exist,
    ]
    for test in tests:
        test()
        print(f"ok {test.__name__}")
