import Foundation

// MARK: - Item Types

enum MediaItemType: String, Codable, CaseIterable {
    case iptvChannel
    case musicSong
    case vodItem
}

// MARK: - Favorite

struct FavoriteItem: Codable, Identifiable, Equatable {
    var id: String
    let type: MediaItemType
    let title: String
    let subtitle: String
    let thumbnailURL: String?
    let detailPath: String?  // For restoring context: channel name, song id, vod id
    let addedAt: Date
}

// MARK: - History

struct HistoryItem: Codable, Identifiable, Equatable {
    var id: String
    let type: MediaItemType
    let title: String
    let subtitle: String
    let thumbnailURL: String?
    let detailPath: String?
    var lastPlayedAt: Date
    var playCount: Int
}

// MARK: - Queue

struct QueueItem: Codable, Identifiable, Equatable {
    var id: String
    let type: MediaItemType
    let title: String
    let subtitle: String
    let thumbnailURL: String?
    let detailPath: String?
    let streamURL: String?  // Pre-resolved URL for faster playback
    var order: Int
    let addedAt: Date
}

// MARK: - Playlist (grouped favorites)

struct PlaylistGroup: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var items: [FavoriteItem]
    let createdAt: Date
    var updatedAt: Date
}
