import Foundation
import MediaLibCore

/// 在线音乐轨道
public struct OnlineMusicTrack: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let artist: String
    public let album: String?
    public let duration: TimeInterval
    public let coverURL: String?
    
    public init(id: String, name: String, artist: String, album: String?, duration: TimeInterval, coverURL: String?) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.duration = duration
        self.coverURL = coverURL
    }
}

/// 在线音乐服务
/// 支持网易云音乐、GD Studio、自定义 API
public actor OnlineMusicService {
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 搜索
    
    /// 搜索音乐（支持多源 fallback）
    public func search(query: String, provider: OnlineMusicProvider) async throws -> [OnlineMusicTrack] {
        switch provider {
        case .netease:
            return try await searchNetease(query: query)
        case .gdstudio:
            return try await searchGDStudio(query: query)
        case .custom(let apiBase):
            return try await searchCustom(query: query, apiBase: apiBase)
        }
    }
    
    // MARK: - 播放地址
    
    /// 获取播放地址
    public func playURL(songID: String, provider: OnlineMusicProvider) async throws -> URL {
        switch provider {
        case .netease:
            return try await playURLNetease(songID: songID)
        case .gdstudio:
            return try await playURLGDStudio(songID: songID)
        case .custom(let apiBase):
            return try await playURLCustom(songID: songID, apiBase: apiBase)
        }
    }
    
    // MARK: - 歌词
    
    /// 获取歌词
    public func lyric(songID: String, provider: OnlineMusicProvider) async throws -> String {
        switch provider {
        case .netease:
            return try await lyricNetease(songID: songID)
        case .gdstudio:
            return try await lyricGDStudio(songID: songID)
        case .custom(let apiBase):
            return try await lyricCustom(songID: songID, apiBase: apiBase)
        }
    }
    
    // MARK: - 网易云音乐 API
    
    private func searchNetease(query: String) async throws -> [OnlineMusicTrack] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://music.163.com/api/search/get/web?s=\(encodedQuery)&type=1&limit=30"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]] else {
            throw OnlineMusicError.parseError
        }
        
        return songs.compactMap { song in
            guard let id = song["id"] as? Int,
                  let name = song["name"] as? String else {
                return nil
            }
            
            let artists = (song["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? "Unknown"
            let album = (song["album"] as? [String: Any])?["name"] as? String
            let duration = (song["duration"] as? Double ?? 0) / 1000.0
            let coverURL = (song["album"] as? [String: Any])?["picUrl"] as? String
            
            return OnlineMusicTrack(
                id: String(id),
                name: name,
                artist: artists,
                album: album,
                duration: duration,
                coverURL: coverURL
            )
        }
    }
    
    private func playURLNetease(songID: String) async throws -> URL {
        let urlString = "https://music.163.com/api/song/enhance/player/url?ids=[\(songID)]&br=320000"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first,
              let urlString = first["url"] as? String,
              let playURL = URL(string: urlString) else {
            throw OnlineMusicError.noPlayURL
        }
        
        return playURL
    }
    
    private func lyricNetease(songID: String) async throws -> String {
        let urlString = "https://music.163.com/api/song/lyric?id=\(songID)&lv=-1&tv=-1"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lrc = json["lrc"] as? [String: Any],
              let lyric = lrc["lyric"] as? String else {
            return ""
        }
        
        return lyric
    }
    
    // MARK: - GD Studio API (网易云备用源)
    
    private func searchGDStudio(query: String) async throws -> [OnlineMusicTrack] {
        // GD Studio 使用相同的网易云 API 格式
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://music-api.gdstudio.xyz/api/search/get/web?s=\(encodedQuery)&type=1&limit=30"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        
        return try parseNeteaseSearchResponse(data: data)
    }
    
    private func playURLGDStudio(songID: String) async throws -> URL {
        let urlString = "https://music-api.gdstudio.xyz/api/song/enhance/player/url?ids=[\(songID)]&br=320000"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        
        return try parseNeteasePlayURLResponse(data: data)
    }
    
    private func lyricGDStudio(songID: String) async throws -> String {
        let urlString = "https://music-api.gdstudio.xyz/api/song/lyric?id=\(songID)&lv=-1&tv=-1"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        
        return try parseNeteaseLyricResponse(data: data)
    }
    
    // MARK: - 自定义 API (兼容网易云格式)
    
    private func searchCustom(query: String, apiBase: String) async throws -> [OnlineMusicTrack] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(apiBase)/api/search/get/web?s=\(encodedQuery)&type=1&limit=30"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        
        return try parseNeteaseSearchResponse(data: data)
    }
    
    private func playURLCustom(songID: String, apiBase: String) async throws -> URL {
        let urlString = "\(apiBase)/api/song/enhance/player/url?ids=[\(songID)]&br=320000"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        
        return try parseNeteasePlayURLResponse(data: data)
    }
    
    private func lyricCustom(songID: String, apiBase: String) async throws -> String {
        let urlString = "\(apiBase)/api/song/lyric?id=\(songID)&lv=-1&tv=-1"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        
        return try parseNeteaseLyricResponse(data: data)
    }
    
    // MARK: - 响应解析辅助方法
    
    private func parseNeteaseSearchResponse(data: Data) throws -> [OnlineMusicTrack] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]] else {
            throw OnlineMusicError.parseError
        }
        
        return songs.compactMap { song in
            guard let id = song["id"] as? Int,
                  let name = song["name"] as? String else {
                return nil
            }
            
            let artists = (song["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? "Unknown"
            let album = (song["album"] as? [String: Any])?["name"] as? String
            let duration = (song["duration"] as? Double ?? 0) / 1000.0
            let coverURL = (song["album"] as? [String: Any])?["picUrl"] as? String
            
            return OnlineMusicTrack(
                id: String(id),
                name: name,
                artist: artists,
                album: album,
                duration: duration,
                coverURL: coverURL
            )
        }
    }
    
    private func parseNeteasePlayURLResponse(data: Data) throws -> URL {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first,
              let urlString = first["url"] as? String,
              let playURL = URL(string: urlString) else {
            throw OnlineMusicError.noPlayURL
        }
        
        return playURL
    }
    
    private func parseNeteaseLyricResponse(data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lrc = json["lrc"] as? [String: Any],
              let lyric = lrc["lyric"] as? String else {
            return ""
        }
        
        return lyric
    }
}

// MARK: - 在线音乐提供商

public enum OnlineMusicProvider: Codable, Sendable {
    case netease
    case gdstudio
    case custom(String)  // API base URL
    
    public var displayName: String {
        switch self {
        case .netease: return "网易云音乐"
        case .gdstudio: return "GD Studio"
        case .custom: return "自定义"
        }
    }
}

// MARK: - 错误

public enum OnlineMusicError: LocalizedError {
    case invalidURL
    case parseError
    case noPlayURL
    case networkError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 API 地址"
        case .parseError:
            return "解析响应失败"
        case .noPlayURL:
            return "未找到播放地址"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}
