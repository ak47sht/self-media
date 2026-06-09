import Foundation

struct IPTVRoute: Codable, Identifiable, Equatable {
    var id: String { url }
    let url: String
    let playURL: String
    let sourceName: String
    let group: String
    let label: String
    let browserPlayable: Bool
}

struct IPTVChannel: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let group: String
    let logo: String
    let sourceName: String
    let url: String
    let playURL: String
    let browserPlayable: Bool
    let routes: [IPTVRoute]
    let detailPath: String
}

struct IPTVChannelsResponse: Codable, Equatable {
    let channels: [IPTVChannel]
    let count: Int
    let groups: [String]
    let errors: [String]
    let showLimited: Bool
}

struct Song: Codable, Identifiable, Equatable {
    let id: String
    let source: String
    let name: String
    let artist: String
    let album: String?
    let cover: String?
    let duration: String?
}

struct MusicSearchResponse: Codable, Equatable {
    let songs: [Song]
    let count: Int
    let cache: String?
    let ncm_cache: String?
}

struct PlayURLResponse: Codable, Equatable {
    let url: String?
    let provider: String?
    let error: String?
}

struct LyricLine: Codable, Identifiable, Equatable {
    var id: Double { time }
    let time: Double
    let text: String
}

struct LyricsResponse: Codable, Equatable {
    let text: String
    let lines: [LyricLine]
}
