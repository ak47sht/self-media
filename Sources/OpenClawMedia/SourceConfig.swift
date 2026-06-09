import Foundation

enum MediaSourceKind: String, Codable, CaseIterable, Identifiable {
    case backendMovie
    case backendMusic
    case iptvM3U
    case aiImageProvider
    case openlist
    case customParser

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .backendMovie: return "Movie backend"
        case .backendMusic: return "Music backend"
        case .iptvM3U: return "IPTV / M3U"
        case .aiImageProvider: return "AI image provider"
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
                id: "local-m3u-placeholder",
                name: "Local IPTV playlist",
                kind: .iptvM3U,
                baseURL: nil,
                fileURL: nil,
                enabled: false,
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
                baseURL: URL(string: "https://api.example.com/v1"),
                fileURL: nil,
                enabled: false,
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
