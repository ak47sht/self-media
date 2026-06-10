import Foundation

enum MediaSourceKind: String, Codable, CaseIterable, Identifiable {
    case backendMovie
    case backendMusic
    case iptvM3U
    case xtreamCodes
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
        case .xtreamCodes: return "Xtream Codes"
        case .aiImageProvider: return "AI image provider"
        case .vodTVBox: return "TVBox / VOD"
        case .musicBuiltin: return "Unlocked music backend"
        case .openlist: return "OpenList"
        case .customParser: return "Custom parser"
        }
    }
}

enum SourceContentCapability: String, Codable, CaseIterable, Hashable, Identifiable {
    case live
    case vod
    case music
    case image

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .live: return "Live"
        case .vod: return "VOD"
        case .music: return "Music"
        case .image: return "Image"
        }
    }
}

enum SourceValidationStatus: String, Codable, Hashable {
    case unknown
    case ready
    case warning
    case unsupported
    case failed

    var displayName: String {
        switch self {
        case .unknown: return "Not checked"
        case .ready: return "Ready"
        case .warning: return "Needs attention"
        case .unsupported: return "Unsupported"
        case .failed: return "Failed"
        }
    }
}

enum SourceDiagnosticSeverity: String, Codable, Hashable {
    case info
    case warning
    case error
}

struct SourceDiagnostic: Codable, Hashable, Identifiable {
    let id: String
    let severity: SourceDiagnosticSeverity
    let message: String

    init(id: String, severity: SourceDiagnosticSeverity, message: String) {
        self.id = id
        self.severity = severity
        self.message = message
    }
}

struct SourceCapability: Codable, Hashable, Identifiable {
    var id: String { type?.rawValue ?? name }
    let name: String
    let enabled: Bool
    let type: SourceContentCapability?

    init(name: String, enabled: Bool, type: SourceContentCapability? = nil) {
        self.name = name
        self.enabled = enabled
        self.type = type
    }

    enum CodingKeys: String, CodingKey {
        case name
        case enabled
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        type = try container.decodeIfPresent(SourceContentCapability.self, forKey: .type)
    }
}

struct MediaSourceConfig: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var kind: MediaSourceKind
    var baseURL: URL?
    var fileURL: URL?
    var username: String?
    var password: String?
    var enabled: Bool
    var priority: Int
    var tags: [String]
    var capabilities: [SourceCapability]
    var validationStatus: SourceValidationStatus
    var diagnostics: [SourceDiagnostic]

    init(
        id: String,
        name: String,
        kind: MediaSourceKind,
        baseURL: URL?,
        fileURL: URL?,
        username: String? = nil,
        password: String? = nil,
        enabled: Bool,
        priority: Int,
        tags: [String],
        capabilities: [SourceCapability],
        validationStatus: SourceValidationStatus = .unknown,
        diagnostics: [SourceDiagnostic] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.fileURL = fileURL
        self.username = username
        self.password = password
        self.enabled = enabled
        self.priority = priority
        self.tags = tags
        self.capabilities = capabilities
        self.validationStatus = validationStatus
        self.diagnostics = diagnostics
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case baseURL
        case fileURL
        case username
        case password
        case enabled
        case priority
        case tags
        case capabilities
        case validationStatus
        case diagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(MediaSourceKind.self, forKey: .kind)
        baseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL)
        fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        password = try container.decodeIfPresent(String.self, forKey: .password)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        priority = try container.decode(Int.self, forKey: .priority)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        capabilities = try container.decodeIfPresent([SourceCapability].self, forKey: .capabilities) ?? SourceDiagnostics.defaultCapabilities(for: kind)
        validationStatus = try container.decodeIfPresent(SourceValidationStatus.self, forKey: .validationStatus) ?? .unknown
        diagnostics = try container.decodeIfPresent([SourceDiagnostic].self, forKey: .diagnostics) ?? []
    }

    var endpointSummary: String {
        if let host = baseURL?.host { return host }
        if let fileURL { return fileURL.lastPathComponent }
        return "local configuration"
    }
}

enum SourceDiagnostics {
    static func defaultCapabilities(for kind: MediaSourceKind, musicUnlocked: Bool = false) -> [SourceCapability] {
        switch kind {
        case .backendMovie:
            return [
                SourceCapability(name: "Live", enabled: true, type: .live),
                SourceCapability(name: "Backend normalized", enabled: true),
                SourceCapability(name: "External player ready", enabled: true),
            ]
        case .backendMusic:
            return [
                SourceCapability(name: "Music", enabled: true, type: .music),
                SourceCapability(name: "Search", enabled: true),
                SourceCapability(name: "Lyrics", enabled: true),
            ]
        case .iptvM3U:
            return [
                SourceCapability(name: "Live", enabled: true, type: .live),
                SourceCapability(name: "M3U playlist", enabled: true),
                SourceCapability(name: "External player ready", enabled: true),
            ]
        case .xtreamCodes:
            return [
                SourceCapability(name: "Live", enabled: true, type: .live),
                SourceCapability(name: "VOD", enabled: true, type: .vod),
                SourceCapability(name: "Series planned", enabled: false),
            ]
        case .vodTVBox:
            return [
                SourceCapability(name: "VOD", enabled: true, type: .vod),
                SourceCapability(name: "TVBox direct API", enabled: true),
                SourceCapability(name: "Parser support limited", enabled: false),
            ]
        case .aiImageProvider:
            return [
                SourceCapability(name: "Image", enabled: true, type: .image),
                SourceCapability(name: "Provider/API request", enabled: true),
                SourceCapability(name: "Keychain secret", enabled: true),
            ]
        case .musicBuiltin:
            return [
                SourceCapability(name: "Music", enabled: musicUnlocked, type: .music),
                SourceCapability(name: "Search", enabled: musicUnlocked),
                SourceCapability(name: "Unlock required", enabled: !musicUnlocked),
            ]
        case .openlist:
            return [
                SourceCapability(name: "VOD", enabled: false, type: .vod),
                SourceCapability(name: "OpenList browser", enabled: false),
            ]
        case .customParser:
            return [
                SourceCapability(name: "VOD", enabled: false, type: .vod),
                SourceCapability(name: "Custom parser", enabled: false),
            ]
        }
    }

    static func validate(_ source: MediaSourceConfig) -> (SourceValidationStatus, [SourceDiagnostic]) {
        if !source.enabled {
            return (.warning, [SourceDiagnostic(id: "disabled", severity: .info, message: "Source is disabled and will not be used.")])
        }

        switch source.kind {
        case .openlist:
            return (.unsupported, [SourceDiagnostic(id: "openlist-unsupported", severity: .warning, message: "OpenList is tracked as a future source type; browsing/playback is not implemented in this build.")])
        case .customParser:
            return (.unsupported, [SourceDiagnostic(id: "custom-parser-unsupported", severity: .warning, message: "Custom parser sources are not executed in this build. Use M3U or TVBox-compatible sources.")])
        case .musicBuiltin:
            if source.capabilities.contains(where: { $0.name == "Unlock required" && $0.enabled }) {
                return (.warning, [SourceDiagnostic(id: "music-locked", severity: .warning, message: "Built-in music sources require the local unlock code before search/playback is enabled.")])
            }
            return (.ready, [SourceDiagnostic(id: "music-ready", severity: .info, message: "Music source can be used for search and playback.")])
        case .xtreamCodes:
            guard let url = source.baseURL else {
                return (.warning, [SourceDiagnostic(id: "missing-url", severity: .warning, message: "Xtream source needs a provider base URL.")])
            }
            if url.host?.contains("example") == true {
                return (.warning, [SourceDiagnostic(id: "placeholder-url", severity: .warning, message: "This Xtream source still points at placeholder configuration. Add your own provider URL before using it.")])
            }
            if (source.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (.warning, [SourceDiagnostic(id: "missing-username", severity: .warning, message: "Xtream source needs a username.")])
            }
            if (source.password ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (.warning, [SourceDiagnostic(id: "missing-password", severity: .warning, message: "Xtream source needs a password.")])
            }
            return (.ready, [SourceDiagnostic(id: "ready", severity: .info, message: "Xtream source is ready for live and VOD API calls.")])
        case .backendMovie, .backendMusic, .iptvM3U, .vodTVBox, .aiImageProvider:
            guard let url = source.baseURL ?? source.fileURL else {
                return (.warning, [SourceDiagnostic(id: "missing-url", severity: .warning, message: "No source URL is configured yet.")])
            }
            if url.host?.contains("example") == true {
                return (.warning, [SourceDiagnostic(id: "placeholder-url", severity: .warning, message: "This source still points at placeholder configuration. Add your own URL before using it.")])
            }
            return (.ready, [SourceDiagnostic(id: "ready", severity: .info, message: "Source configuration is ready for local parsing or direct API calls.")])
        }
    }

    static func parsingFailure(kind: MediaSourceKind, error: Error) -> String {
        switch kind {
        case .iptvM3U:
            return "IPTV source could not be parsed. Check that the configured URL returns a UTF-8 M3U playlist. Details: \(error.localizedDescription)"
        case .vodTVBox:
            return "VOD source could not be parsed. Only TVBox-compatible JSON configs are supported in this build. Details: \(error.localizedDescription)"
        default:
            return "Source failed: \(error.localizedDescription)"
        }
    }

    static func playbackFailure(kind: MediaSourceKind, error: Error) -> String {
        switch kind {
        case .vodTVBox:
            return "VOD playback failed. The source may require parser/sniffer support that is not implemented here, or it returned an invalid URL. Details: \(error.localizedDescription)"
        case .backendMusic, .musicBuiltin:
            return "Music playback failed. Check that the selected music source supports play-url resolution. Details: \(error.localizedDescription)"
        case .iptvM3U, .backendMovie:
            return "Video playback failed. Check that the stream URL is reachable and supported by AVPlayer. Details: \(error.localizedDescription)"
        default:
            return "Playback failed: \(error.localizedDescription)"
        }
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
                username: nil,
                password: nil,
                enabled: true,
                priority: 10,
                tags: ["IPTV", "normalized"],
                capabilities: SourceDiagnostics.defaultCapabilities(for: .backendMovie)
            ),
            MediaSourceConfig(
                id: "backend-music",
                name: "Music Lite backend",
                kind: .backendMusic,
                baseURL: config.musicBaseURL,
                fileURL: nil,
                username: nil,
                password: nil,
                enabled: true,
                priority: 20,
                tags: ["Music", "lyrics"],
                capabilities: SourceDiagnostics.defaultCapabilities(for: .backendMusic)
            ),
            MediaSourceConfig(
                id: "builtin-music-unlocked",
                name: "Unlocked music backend sources",
                kind: .musicBuiltin,
                baseURL: config.musicBaseURL,
                fileURL: nil,
                username: nil,
                password: nil,
                enabled: config.isMusicUnlocked,
                priority: 25,
                tags: ["Music", "built-in"],
                capabilities: SourceDiagnostics.defaultCapabilities(for: .musicBuiltin, musicUnlocked: config.isMusicUnlocked)
            ),
            MediaSourceConfig(
                id: "local-m3u-placeholder",
                name: "Local IPTV playlist",
                kind: .iptvM3U,
                baseURL: config.iptvPlaylistURL,
                fileURL: nil,
                username: nil,
                password: nil,
                enabled: config.iptvPlaylistURL != nil,
                priority: 30,
                tags: ["M3U", "local"],
                capabilities: SourceDiagnostics.defaultCapabilities(for: .iptvM3U)
            ),
            MediaSourceConfig(
                id: "ai-image-provider-placeholder",
                name: "AI image provider",
                kind: .aiImageProvider,
                baseURL: config.aiImageProviderBaseURL,
                fileURL: nil,
                username: nil,
                password: nil,
                enabled: config.aiImageProviderBaseURL?.host?.contains("example") == false,
                priority: 40,
                tags: ["AI", "image", "keychain"],
                capabilities: SourceDiagnostics.defaultCapabilities(for: .aiImageProvider)
            ),
        ]
    }
}
