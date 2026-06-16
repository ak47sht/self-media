import Foundation
import MediaLibCore

/// 在线音乐服务：网易云音乐 + GD Studio + 自定义 LX Music 兼容源
struct OnlineMusicService {
    enum Provider: String, Codable {
        case netease
        case gdstudio
        case custom
    }
    
    struct Song: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var artist: String
        var album: String?
        var duration: Int? // seconds
        var source: Provider
        
        var displayArtist: String {
            artist.isEmpty ? "未知艺术家" : artist
        }
    }
    
    struct SearchResult {
        var songs: [Song]
        var source: Provider
    }
    
    struct PlayURLResult {
        var url: String
        var bitrate: Int?
        var format: String?
    }
    
    struct Lyric {
        var lrc: String? // LRC format
        var tlyric: String? // Translated lyric
    }
    
    // MARK: - Search
    
    /// 搜索歌曲：依次尝试 netease → gdstudio，返回首个成功结果
    func search(query: String, neteaseAPI: String?, gdstudioAPI: String?) async throws -> SearchResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Try Netease first
        if let api = neteaseAPI, !api.isEmpty {
            if let result = try? await searchNetease(query: trimmed, apiBase: api) {
                return result
            }
        }
        
        // Fallback to GD Studio
        if let api = gdstudioAPI, !api.isEmpty {
            if let result = try? await searchGDStudio(query: trimmed, apiBase: api) {
                return result
            }
        }
        
        return nil
    }
    
    private func searchNetease(query: String, apiBase: String) async throws -> SearchResult? {
        var components = URLComponents(string: apiBase.trimmingCharacters(in: .init(charactersIn: "/")))
        components?.path = "/cloudsearch"
        components?.queryItems = [
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "type", value: "1") // 1=单曲
        ]
        guard let url = components?.url else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        
        let decoded = try JSONDecoder().decode(NeteaseSearchResponse.self, from: data)
        guard let songs = decoded.result?.songs, !songs.isEmpty else { return nil }
        
        let mapped = songs.compactMap { item -> Song? in
            guard let id = item.id else { return nil }
            return Song(
                id: "netease:\(id)",
                name: item.name ?? "未知曲目",
                artist: item.ar?.compactMap(\.name).joined(separator: " / ") ?? "",
                album: item.al?.name,
                duration: (item.dt ?? 0) / 1000,
                source: .netease
            )
        }
        
        return SearchResult(songs: mapped, source: .netease)
    }
    
    private func searchGDStudio(query: String, apiBase: String) async throws -> SearchResult? {
        var components = URLComponents(string: apiBase)
        components?.queryItems = [
            URLQueryItem(name: "source", value: "netease"),
            URLQueryItem(name: "types", value: "search"),
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "30")
        ]
        guard let url = components?.url else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        
        let decoded = try JSONDecoder().decode(GDStudioSearchResponse.self, from: data)
        guard let items = decoded.data, !items.isEmpty else { return nil }
        
        let mapped = items.compactMap { item -> Song? in
            guard let id = item.songid else { return nil }
            return Song(
                id: "gdstudio:\(id)",
                name: item.name ?? "未知曲目",
                artist: item.artist?.joined(separator: " / ") ?? "",
                album: item.album,
                duration: item.interval,
                source: .gdstudio
            )
        }
        
        return SearchResult(songs: mapped, source: .gdstudio)
    }
    
    // MARK: - Play URL
    
    /// 获取播放地址：根据 song.source 路由到对应 provider
    func playURL(song: Song, neteaseAPI: String?, gdstudioAPI: String?, quality: String = "320") async throws -> PlayURLResult? {
        switch song.source {
        case .netease:
            guard let api = neteaseAPI, !api.isEmpty else { return nil }
            return try await playURLNetease(songID: extractID(song.id), apiBase: api, quality: quality)
        case .gdstudio:
            guard let api = gdstudioAPI, !api.isEmpty else { return nil }
            return try await playURLGDStudio(songID: extractID(song.id), apiBase: api)
        case .custom:
            return nil // TODO: custom source
        }
    }
    
    private func playURLNetease(songID: String, apiBase: String, quality: String) async throws -> PlayURLResult? {
        var components = URLComponents(string: apiBase.trimmingCharacters(in: .init(charactersIn: "/")))
        components?.path = "/song/url/v1"
        components?.queryItems = [
            URLQueryItem(name: "id", value: songID),
            URLQueryItem(name: "level", value: qualityToLevel(quality))
        ]
        guard let url = components?.url else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        
        let decoded = try JSONDecoder().decode(NeteaseSongURLResponse.self, from: data)
        guard let first = decoded.data?.first, let urlStr = first.url, !urlStr.isEmpty else { return nil }
        
        return PlayURLResult(url: urlStr, bitrate: first.br, format: first.type)
    }
    
    private func playURLGDStudio(songID: String, apiBase: String) async throws -> PlayURLResult? {
        var components = URLComponents(string: apiBase)
        components?.queryItems = [
            URLQueryItem(name: "source", value: "netease"),
            URLQueryItem(name: "types", value: "url"),
            URLQueryItem(name: "id", value: songID),
            URLQueryItem(name: "br", value: "320000")
        ]
        guard let url = components?.url else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        
        let decoded = try JSONDecoder().decode(GDStudioURLResponse.self, from: data)
        guard let urlStr = decoded.url, !urlStr.isEmpty else { return nil }
        
        return PlayURLResult(url: urlStr, bitrate: decoded.br, format: nil)
    }
    
    // MARK: - Lyric
    
    /// 获取歌词：依次尝试 netease → gdstudio
    func lyric(song: Song, neteaseAPI: String?, gdstudioAPI: String?) async throws -> Lyric? {
        switch song.source {
        case .netease:
            if let api = neteaseAPI, !api.isEmpty {
                return try? await lyricNetease(songID: extractID(song.id), apiBase: api)
            }
        case .gdstudio:
            if let api = gdstudioAPI, !api.isEmpty {
                return try? await lyricGDStudio(songID: extractID(song.id), apiBase: api)
            }
        case .custom:
            break
        }
        return nil
    }
    
    private func lyricNetease(songID: String, apiBase: String) async throws -> Lyric? {
        var components = URLComponents(string: apiBase.trimmingCharacters(in: .init(charactersIn: "/")))
        components?.path = "/lyric"
        components?.queryItems = [URLQueryItem(name: "id", value: songID)]
        guard let url = components?.url else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        
        let decoded = try JSONDecoder().decode(NeteaseLyricResponse.self, from: data)
        return Lyric(lrc: decoded.lrc?.lyric, tlyric: decoded.tlyric?.lyric)
    }
    
    private func lyricGDStudio(songID: String, apiBase: String) async throws -> Lyric? {
        var components = URLComponents(string: apiBase)
        components?.queryItems = [
            URLQueryItem(name: "source", value: "netease"),
            URLQueryItem(name: "types", value: "lyric"),
            URLQueryItem(name: "id", value: songID)
        ]
        guard let url = components?.url else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        
        let decoded = try JSONDecoder().decode(GDStudioLyricResponse.self, from: data)
        return Lyric(lrc: decoded.lyric, tlyric: decoded.tlyric)
    }
    
    // MARK: - Helpers
    
    private func extractID(_ fullID: String) -> String {
        // "netease:123456" → "123456"
        fullID.split(separator: ":").last.map(String.init) ?? fullID
    }
    
    private func qualityToLevel(_ quality: String) -> String {
        switch quality {
        case "128": return "standard"
        case "320": return "higher"
        case "flac": return "lossless"
        default: return "higher"
        }
    }
}

// MARK: - API Response Models

private struct NeteaseSearchResponse: Codable {
    var result: NeteaseSearchResult?
}

private struct NeteaseSearchResult: Codable {
    var songs: [NeteaseSong]?
}

private struct NeteaseSong: Codable {
    var id: Int?
    var name: String?
    var ar: [NeteaseArtist]?
    var al: NeteaseAlbum?
    var dt: Int? // duration ms
}

private struct NeteaseArtist: Codable {
    var name: String?
}

private struct NeteaseAlbum: Codable {
    var name: String?
}

private struct NeteaseSongURLResponse: Codable {
    var data: [NeteaseSongURL]?
}

private struct NeteaseSongURL: Codable {
    var url: String?
    var br: Int?
    var type: String?
}

private struct NeteaseLyricResponse: Codable {
    var lrc: NeteaseLyricItem?
    var tlyric: NeteaseLyricItem?
}

private struct NeteaseLyricItem: Codable {
    var lyric: String?
}

private struct GDStudioSearchResponse: Codable {
    var data: [GDStudioSong]?
    
    var isEmpty: Bool { data?.isEmpty ?? true }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        data = try? container.decode([GDStudioSong].self)
    }
}

private struct GDStudioSong: Codable {
    var songid: String?
    var name: String?
    var artist: [String]?
    var album: String?
    var interval: Int?
}

private struct GDStudioURLResponse: Codable {
    var url: String?
    var br: Int?
}

private struct GDStudioLyricResponse: Codable {
    var lyric: String?
    var tlyric: String?
}
