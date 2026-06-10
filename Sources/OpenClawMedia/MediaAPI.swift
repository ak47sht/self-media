import Foundation
import Combine

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

    func iptvChannel(name: String, showLimited: Bool = true) async throws -> IPTVChannel {
        try await get(base: config.movieBaseURL, path: "/api/iptv/channel", queryItems: [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "show_limited", value: showLimited ? "1" : "0")
        ])
    }

    func searchSongs(query: String) async throws -> MusicSearchResponse {
        try await get(base: config.musicBaseURL, path: "/api/search", queryItems: [URLQueryItem(name: "q", value: query)])
    }

    func searchSongs(base: URL, query: String) async throws -> MusicSearchResponse {
        try await get(base: base, path: "/api/search", queryItems: [URLQueryItem(name: "q", value: query)])
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

    func playURL(base: URL, for song: Song) async throws -> PlayURLResponse {
        try await get(base: base, path: "/api/play-url", queryItems: [
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

    func lyrics(base: URL, for song: Song) async throws -> LyricsResponse {
        try await get(base: base, path: "/api/lyrics", queryItems: [
            URLQueryItem(name: "id", value: song.id),
            URLQueryItem(name: "source", value: song.source),
            URLQueryItem(name: "name", value: song.name),
            URLQueryItem(name: "artist", value: song.artist)
        ])
    }

    func generateImage(prompt: String, negativePrompt: String, size: String) async throws -> AIImageGenerationResponse {
        guard let base = config.aiImageProviderBaseURL else { throw URLError(.badURL) }
        let cleanModel = config.aiImageProviderModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = AIImageGenerationRequest(
            model: cleanModel.isEmpty || cleanModel == "provider-default" ? "dall-e-3" : cleanModel,
            prompt: prompt,
            negativePrompt: negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : negativePrompt,
            size: size.replacingOccurrences(of: "×", with: "x"),
            n: 1
        )
        return try await post(base: base, path: "/images/generations", body: request, bearerToken: config.aiImageAPIKey)
    }

    // MARK: - VOD (TVBox direct API)

    /// Search/list a TVBox source directly. Empty query falls back to ac=list so a configured source can show content before typing.
    func searchVOD(source: VODSource, query: String) async throws -> VODSearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = trimmed.isEmpty
            ? [URLQueryItem(name: "ac", value: "list"), URLQueryItem(name: "pg", value: "1")]
            : [URLQueryItem(name: "wd", value: trimmed), URLQueryItem(name: "pg", value: "1")]
        return try await get(base: source.api, path: "", queryItems: items)
    }

    /// Fetch detail for a VOD item from a TVBox source.
    func vodDetail(source: VODSource, id: String) async throws -> VODDetailResponse {
        let items = [URLQueryItem(name: "ac", value: "detail"), URLQueryItem(name: "ids", value: id)]
        return try await get(base: source.api, path: "", queryItems: items)
    }

    /// Resolve a play URL from a TVBox source — some sources may need server parsing.
    func vodPlay(source: VODSource, flag: String, id: String) async throws -> VODPlayResponse {
        let items = [URLQueryItem(name: "ac", value: "play"), URLQueryItem(name: "flag", value: flag), URLQueryItem(name: "id", value: id)]
        let url = try await get(base: source.api, path: "", queryItems: items) as VODPlayResponse
        return url
    }

    /// Fetch raw JSON from an arbitrary URL (used for some VOD sources that need two-step resolution).
    func rawGet(url: URL, queryItems: [URLQueryItem] = []) async throws -> Data {
        let cleanPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let resolved = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: resolved)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func get<T: Decodable>(base: URL, path: String, queryItems: [URLQueryItem]) async throws -> T {
        let url = try buildURL(base: base, path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.setValue("OpenClawMedia/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(T.self, from: data)
    }

    private func buildURL(base: URL, path: String, queryItems: [URLQueryItem]) throws -> URL {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let resolvedBase = cleanPath.isEmpty ? base : base.appendingPathComponent(cleanPath)
        guard var components = URLComponents(url: resolvedBase, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if !queryItems.isEmpty {
            var merged = components.queryItems ?? []
            merged.append(contentsOf: queryItems)
            components.queryItems = merged
        }
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func post<T: Decodable, Body: Encodable>(base: URL, path: String, body: Body, bearerToken: String) async throws -> T {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = base.appendingPathComponent(cleanPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(T.self, from: data)
    }
}
