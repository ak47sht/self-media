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

    private func get<T: Decodable>(base: URL, path: String, queryItems: [URLQueryItem]) async throws -> T {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(url: base.appendingPathComponent(cleanPath), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(T.self, from: data)
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
