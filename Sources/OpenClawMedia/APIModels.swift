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

struct AIImageGenerationRequest: Codable, Equatable {
    let model: String
    let prompt: String
    let negativePrompt: String?
    let size: String
    let n: Int

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case negativePrompt = "negative_prompt"
        case size
        case n
    }
}

struct AIImageGenerationData: Codable, Identifiable, Equatable {
    var id: String { url ?? revisedPrompt ?? "image" }
    let url: String?
    let b64Json: String?
    let revisedPrompt: String?

    enum CodingKeys: String, CodingKey {
        case url
        case b64Json = "b64_json"
        case revisedPrompt = "revised_prompt"
    }
}

struct AIImageGenerationResponse: Codable, Equatable {
    let created: Int?
    let data: [AIImageGenerationData]
}
