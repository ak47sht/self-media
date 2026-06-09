import Foundation

final class MediaAPI: ObservableObject {
    private let config: AppConfig
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func iptvChannels(query: String = "", showLimited: Bool = false) async throws -> IPTVChannelsResponse {
        var items: [URLQueryItem] = [URLQueryItem(name: "show_limited", value: showLimited ? "1" : "0")]
        if !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await get(base: config.movieBaseURL, path: "/api/iptv/channels", queryItems: items)
    }

    func searchSongs(query: String) async throws -> MusicSearchResponse {
        try await get(base: config.musicBaseURL, path: "/api/search", queryItems: [URLQueryItem(name: "q", value: query)])
    }

    func playURL(for song: Song) async throws -> PlayURLResponse {
        try await get(base: config.musicBaseURL, path: "/api/play-url", queryItems: [
            URLQueryItem(name: "id", value: song.id),
            URLQueryItem(name: "source", value: song.source),
            URLQueryItem(name: "name", value: song.name),
            URLQueryItem(name: "artist", value: song.artist),
            URLQueryItem(name: "duration", value: song.duration ?? ""),
            URLQueryItem(name: "br", value: "320kmp3")
        ])
    }

    func lyrics(for song: Song) async throws -> LyricsResponse {
        try await get(base: config.musicBaseURL, path: "/api/lyrics", queryItems: [
            URLQueryItem(name: "id", value: song.id),
            URLQueryItem(name: "source", value: song.source),
            URLQueryItem(name: "name", value: song.name),
            URLQueryItem(name: "artist", value: song.artist)
        ])
    }

    private func get<T: Decodable>(base: URL, path: String, queryItems: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(T.self, from: data)
    }
}
