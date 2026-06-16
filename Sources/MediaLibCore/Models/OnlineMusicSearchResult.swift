import Foundation

/// Online music search result
public struct OnlineMusicSearchResult: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let artist: String
    public let album: String?
    public let duration: Int? // in seconds
    public let provider: String
    public let providerSongID: String
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        artist: String,
        album: String? = nil,
        duration: Int? = nil,
        provider: String,
        providerSongID: String
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.duration = duration
        self.provider = provider
        self.providerSongID = providerSongID
    }
}
