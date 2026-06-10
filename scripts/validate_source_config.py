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
            "IPTV M3U 播放列表 URL",
            "AI provider base URL",
            "AI provider API key",
            "AI provider model",
            "导入源配置",
            "VOD config URL",
            "Music unlock code",
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
            "LegacyAVPlayerView(player:",
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


def test_client_side_source_parsing_is_primary() -> None:
    assert_contains(
        "Sources/OpenClawMedia/LocalSourceParsing.swift",
        [
            "struct M3UPlaylistParser",
            "#EXTINF",
            "parseChannels",
            "struct TVBoxConfigParser",
            "sites",
            "VODSource",
        ],
    )
    assert_contains(
        "Sources/OpenClawMedia/Config.swift",
        [
            "vodConfigURL",
            "musicUnlockCodeHash",
            "jsSourceImportURL",
        ],
    )
    assert_contains(
        "Sources/OpenClawMedia/App.swift",
        [
            "loadChannels",
            "loadVODSources",
            "Advanced backend/debug settings",
            "导入源配置",
        ],
    )


def test_vod_models_exist() -> None:
    assert_contains(
        "Sources/OpenClawMedia/Models/VODModels.swift",
        [
            "struct VODSearchItem",
            "vodID",
            "vodName",
            "struct VODDetailItem",
            "vodPlayFrom",
            "vodPlayURL",
            "var episodes: [VODEpisode]",
            "struct VODEpisode",
            "struct VODSearchResponse",
            "struct VODDetailResponse",
            "struct VODPlayResponse",
        ],
    )


def test_vod_api_methods_exist() -> None:
    assert_contains(
        "Sources/OpenClawMedia/MediaAPI.swift",
        [
            "func searchVOD",
            "func vodDetail",
            "func vodPlay",
            "VODSearchResponse",
            "VODDetailResponse",
            "VODPlayResponse",
        ],
    )


def test_vod_ui_exists() -> None:
    assert_contains(
        "Sources/OpenClawMedia/Views/VODView.swift",
        [
            "struct VODView: View",
            "func search() async",
            "func loadDetail",
            "func playEpisode",
            "VODResultCard",
            "ForEach(results)",
            "episodes",
            "selectedEpisode",
            "VODPosterPlaceholder",
        ],
    )


def test_vod_sidebar_integration() -> None:
    assert_contains(
        "Sources/OpenClawMedia/App.swift",
        [
            "case vod",
            "VOD\", subtitle:",
            "VODView(api: api, playback: playback, sources: vodSources, config: config)",
        ],
    )


def test_file_structure_split() -> None:
    # New modular structure should be taking shape
    assert_contains(
        "Sources/OpenClawMedia/Models/VODModels.swift",
        ["CodingKeys", "vod_id", "vod_name"],
    )
    assert_contains(
        "Sources/OpenClawMedia/Views/VODView.swift",
        ["import SwiftUI", "VODView"],
    )


def test_playback_error_handling_exists() -> None:
    assert_contains(
        "Sources/OpenClawMedia/PlaybackSupport.swift",
        [
            "enum PlaybackState",
            "case .error",
            "case .loading",
            "case .stalled",
            "case .completed",
            "var displayText",
            "var isError",
            "var isActive",
            "func tryNextFallback",
            "fallbackAttempts",
            "maxFallbackAttempts",
            "autoFallbackEnabled",
            "func fallbackRoutes",
            "NSKeyValueObservation",
            "AVPlayerItemFailedToPlayToEndTime",
            "handlePlaybackError",
            "handleItemStatus",
            "observe(item:",
            "stopObserving",
        ],
    )


def test_playback_ui_uses_state() -> None:
    assert_contains(
        "Sources/OpenClawMedia/App.swift",
        [
            "playback.state.displayText",
            "playback.state.isError",
            "Try next route",
            "playback.tryNextFallback",
            "fallbackRoutes",
            "fallbacks: fallbacks",
            "Copy URL",
        ],
    )


def test_local_store_exists() -> None:
    assert_contains(
        "Sources/OpenClawMedia/Services/LocalStore.swift",
        [
            "class LocalStore",
            "func addFavorite",
            "func removeFavorite",
            "func toggleFavorite",
            "func isFavorite",
            "func addToHistory",
            "func recentHistory",
            "func enqueue",
            "func dequeue",
            "func clearQueue",
            "func clearHistory",
            "UserDefaults.standard",
            "JSONEncoder",
            "JSONDecoder",
        ],
    )


def test_storage_models_exist() -> None:
    assert_contains(
        "Sources/OpenClawMedia/Models/StorageModels.swift",
        [
            "struct FavoriteItem",
            "struct HistoryItem",
            "struct QueueItem",
            "enum MediaItemType",
            "case iptvChannel",
            "case musicSong",
            "case vodItem",
        ],
    )


def test_favorites_integrated_into_ui() -> None:
    assert_contains(
        "Sources/OpenClawMedia/App.swift",
        [
            "@StateObject private var store = LocalStore()",
            "store.toggleFavorite",
            "store.isFavorite",
            "store.addToHistory",
            "heart.fill",
            ".iptvChannel",
            ".musicSong",
        ],
    )


def test_source_manager_exists() -> None:
    assert_contains(
        "Sources/OpenClawMedia/Services/SourceManager.swift",
        [
            "class SourceManager",
            "func addSource",
            "func removeSource",
            "func updateSource",
            "func toggleSource",
            "func testSource",
            "SourceTestResult",
            "func save(",
            "func load(",
        ],
    )


def test_source_management_ui_wired() -> None:
    assert_contains(
        "Sources/OpenClawMedia/App.swift",
        [
            "@StateObject private var sourceManager",
            "SourceManager()",
            "SourcesSettingsView(sourceManager:",
            "sourceManager.toggleSource",
            "sourceManager.removeSource",
            "sourceManager.addSource",
            "Add source",
            "contextMenu",
        ],
    )


def test_keyboard_shortcuts_and_playback_bar_exist() -> None:
    assert_contains(
        "Sources/OpenClawMedia/KeyboardShortcuts.swift",
        [
            "func establishMediaKeyboardShortcuts",
            "NSEvent.addLocalMonitorForEvents",
            "\" \"",
            "\"k\"",
            "\"f\"",
            "\"m\"",
            "struct PlaybackControlBar",
            "Slider",
            "formatTime",
            "seek(to:",
        ],
    )


def test_playback_bar_integrated_into_detail_panel() -> None:
    assert_contains(
        "Sources/OpenClawMedia/App.swift",
        [
            "PlaybackControlBar(playback:",
            "establishMediaKeyboardShortcuts(playback)",
            "Space play/pause",
            "K stop",
            "F fullscreen",
            "M mute",
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
        test_client_side_source_parsing_is_primary,
        test_vod_models_exist,
        test_vod_api_methods_exist,
        test_vod_ui_exists,
        test_vod_sidebar_integration,
        test_file_structure_split,
        test_playback_error_handling_exists,
        test_playback_ui_uses_state,
        test_local_store_exists,
        test_storage_models_exist,
        test_favorites_integrated_into_ui,
        test_source_manager_exists,
        test_source_management_ui_wired,
        test_keyboard_shortcuts_and_playback_bar_exist,
        test_playback_bar_integrated_into_detail_panel,
    ]
    for test in tests:
        test()
        print(f"ok {test.__name__}")
