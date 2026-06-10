import Foundation

enum MediaSourceKind: String, Codable, CaseIterable, Identifiable {
    case backendMovie
    case backendMusic
    case iptvM3U
    case aiImageProvider
    case vodTVBox
    case musicBuiltin
    case openlist
    case customParser

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .backendMovie: return "Movie backend"
        case .backendMusic: return "Music backend"
        case .iptvM3U: return "IPTV / M3U"
        case .aiImageProvider: return "AI image provider"
        case .vodTVBox: return "TVBox / VOD"
        case .musicBuiltin: return "Music built-in"
        case .openlist: return "OpenList"
        case .customParser: return "Custom parser"
        }
    }
}

struct SourceCapability: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let enabled: Bool
}

struct MediaSourceConfig: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var kind: MediaSourceKind
    var baseURL: URL?
    var fileURL: URL?
    var enabled: Bool
    var priority: Int
    var tags: [String]
    var capabilities: [SourceCapability]

    var endpointSummary: String {
        if let host = baseURL?.host { return host }
        if let fileURL { return fileURL.lastPathComponent }
        return "local configuration"
    }
}

enum SourcePresets {
    static let builtinTVBoxFeed: URL? = URL(string: "https://raw.githubusercontent.com/FongMi/Release/main/tv/box.conf")
    static let musicUnlockCodeHash = "221a23ba7ffc678de46bb3d4a2b2cced4476daf0ed1f88e23ec22f922c940518"

    static func defaultSources(config: AppConfig) -> [MediaSourceConfig] {
        [
            MediaSourceConfig(
                id: "backend-movie",
                name: "Movie Lite backend",
                kind: .backendMovie,
                baseURL: config.movieBaseURL,
                fileURL: nil,
                enabled: true,
                priority: 10,
                tags: ["IPTV", "normalized"],
                capabilities: [
                    SourceCapability(name: "Backend normalized", enabled: true),
                    SourceCapability(name: "Direct play locally", enabled: true),
                    SourceCapability(name: "External player ready", enabled: true),
                ]
            ),
            MediaSourceConfig(
                id: "backend-music",
                name: "Music Lite backend",
                kind: .backendMusic,
                baseURL: config.musicBaseURL,
                fileURL: nil,
                enabled: true,
                priority: 20,
                tags: ["Music", "lyrics"],
                capabilities: [
                    SourceCapability(name: "Backend normalized", enabled: true),
                    SourceCapability(name: "Direct play locally", enabled: true),
                    SourceCapability(name: "Lyrics", enabled: true),
                ]
            ),
            MediaSourceConfig(
                id: "builtin-music-unlocked",
                name: "Built-in music sources",
                kind: .musicBuiltin,
                baseURL: config.musicBaseURL,
                fileURL: nil,
                enabled: config.isMusicUnlocked,
                priority: 25,
                tags: ["Music", "built-in"],
                capabilities: [
                    SourceCapability(name: "Search", enabled: config.isMusicUnlocked),
                    SourceCapability(name: "Direct play locally", enabled: config.isMusicUnlocked),
                    SourceCapability(name: "Unlock required", enabled: !config.isMusicUnlocked),
                ]
            ),
            MediaSourceConfig(
                id: "local-m3u-placeholder",
                name: "Local IPTV playlist",
                kind: .iptvM3U,
                baseURL: config.iptvPlaylistURL,
                fileURL: nil,
                enabled: config.iptvPlaylistURL != nil,
                priority: 30,
                tags: ["M3U", "local"],
                capabilities: [
                    SourceCapability(name: "Direct play locally", enabled: true),
                    SourceCapability(name: "External player ready", enabled: true),
                ]
            ),
            MediaSourceConfig(
                id: "ai-image-provider-placeholder",
                name: "AI image provider",
                kind: .aiImageProvider,
                baseURL: config.aiImageProviderBaseURL,
                fileURL: nil,
                enabled: config.aiImageProviderBaseURL?.host?.contains("example") == false,
                priority: 40,
                tags: ["AI", "image", "keychain"],
                capabilities: [
                    SourceCapability(name: "Provider/API request", enabled: true),
                    SourceCapability(name: "Keychain secret", enabled: true),
                    SourceCapability(name: "Model configurable", enabled: true),
                ]
            ),
        ]
    }
}
