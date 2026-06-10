#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def assert_contains(path: str, needles: list[str]) -> None:
    text = (ROOT / path).read_text()
    missing = [needle for needle in needles if needle not in text]
    assert not missing, f"{path} missing: {missing}"


def test_vod_detail_direct_play_precedes_ac_play_fallback() -> None:
    assert_contains(
        "Sources/OpenClawMedia/Views/VODView.swift",
        [
            "VODPlaybackResolver.directResponse(source: source, episode: ep)",
            "var candidates = VODPlaybackResolver.resolve(response: directResp",
            "!candidates.contains(where: { StreamURLNormalizer.looksDirectlyPlayable($0.url) })",
            "try await api.vodPlay(source: source, flag: ep.flag, id: ep.url)",
            "Using detail-provided stream; source play endpoint failed.",
        ],
    )
    assert_contains(
        "Sources/OpenClawMedia/Services/VODPlaybackResolver.swift",
        [
            "static func directResponse(source: VODSource, episode: VODEpisode)",
            "url: episode.url",
            "label: \"detail url\"",
            "direct media URL",
        ],
    )


def test_tvbox_parser_accepts_common_web_config_shapes() -> None:
    assert_contains(
        "Sources/OpenClawMedia/LocalSourceParsing.swift",
        [
            "func parse(_ data: Data, sourceURL: URL? = nil)",
            "normalizeTVBoxJSON(data)",
            "normalizeAPI(rawAPI, type: type, sourceURL: sourceURL)",
            "trimmed.hasPrefix(\"//\")",
            "c == \"/\" && i + 1 < chars.count && chars[i + 1] == \"*\"",
            "replacingOccurrences(of: \",\\\\s*([}\\\\]])\"",
            "URL(string: trimmed, relativeTo: sourceURL.deletingLastPathComponent())",
        ],
    )


def test_source_manager_probes_by_source_kind() -> None:
    assert_contains(
        "Sources/OpenClawMedia/Services/SourceManager.swift",
        [
            "private func probeSource(source: MediaSourceConfig, url: URL, start: Date) async throws -> SourceTestResult",
            "case .iptvM3U:",
            "#EXTM3U",
            "#EXTINF",
            "case .vodTVBox:",
            "TVBoxConfigParser().parse(data, sourceURL: url)",
            "VOD TVBox parsed",
            "case .backendMusic, .musicBuiltin:",
            "/api/search",
            "Music search API",
            "case .backendMovie:",
            "/api/iptv/channels",
            "Movie/IPTV backend API",
        ],
    )


if __name__ == "__main__":
    test_vod_detail_direct_play_precedes_ac_play_fallback()
    print("ok test_vod_detail_direct_play_precedes_ac_play_fallback")
    test_tvbox_parser_accepts_common_web_config_shapes()
    print("ok test_tvbox_parser_accepts_common_web_config_shapes")
    test_source_manager_probes_by_source_kind()
    print("ok test_source_manager_probes_by_source_kind")
