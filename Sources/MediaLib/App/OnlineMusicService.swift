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
    
    /// 显示用的艺术家名称
    public var displayArtist: String {
        artist.isEmpty ? "Unknown" : artist
    }
}

/// 在线音乐服务
/// 支持网易云音乐、GD Studio、自定义 API
public actor OnlineMusicService {
    private let session: URLSession
    private var customBaseURL: String = ""  // 自定义 API 的 base URL
    
    /// Song 类型别名（兼容现有 UI 代码）
    public typealias Song = OnlineMusicTrack
    
    /// 搜索结果（兼容现有 UI 代码）
    public struct SearchResult {
        public let songs: [Song]
    }
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }
    
    /// 设置自定义 API base URL（用于 .custom provider）
    public func setCustomBaseURL(_ url: String) {
        self.customBaseURL = url
    }
    
    // MARK: - 兼容旧 API 的方法
    
    /// 搜索音乐（兼容旧 API 签名）
    public func search(query: String, neteaseAPI: String?, gdstudioAPI: String?) async throws -> SearchResult {
        // 优先使用 neteaseAPI，其次 gdstudioAPI，最后官方源
        let provider: OnlineMusicProvider
        if let apiBase = neteaseAPI {
            customBaseURL = apiBase
            provider = .custom
        } else if let apiBase = gdstudioAPI {
            customBaseURL = apiBase
            provider = .custom
        } else {
            provider = .netease
        }
        
        let tracks = try await search(query: query, provider: provider)
        return SearchResult(songs: tracks)
    }
    
    /// 获取播放地址（兼容旧 API 签名）
    public func playURL(song: Song, neteaseAPI: String?, gdstudioAPI: String?) async throws -> (url: String, lyric: String?) {
        // 优先使用 neteaseAPI，其次 gdstudioAPI，最后官方源
        let provider: OnlineMusicProvider
        if let apiBase = neteaseAPI {
            customBaseURL = apiBase
            provider = .custom
        } else if let apiBase = gdstudioAPI {
            customBaseURL = apiBase
            provider = .custom
        } else {
            provider = .netease
        }
        
        let playURL = try await playURL(songID: song.id, provider: provider)
        let lyricText = try? await lyric(songID: song.id, provider: provider)
        
        return (url: playURL.absoluteString, lyric: lyricText)
    }
    
    // MARK: - 搜索
    
    /// 搜索音乐（支持多源 fallback）
    public func search(query: String, provider: OnlineMusicProvider) async throws -> [OnlineMusicTrack] {
        switch provider {
        case .netease:
            return try await searchNetease(query: query)
        case .gdstudio:
            return try await searchGDStudio(query: query)
        case .custom:
            return try await searchCustom(query: query, apiBase: customBaseURL)
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
        case .custom:
            return try await playURLCustom(songID: songID, apiBase: customBaseURL)
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
        case .custom:
            return try await lyricCustom(songID: songID, apiBase: customBaseURL)
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
        
        let data = try await loadData(for: request)
        
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
        
        let data = try await loadData(for: request)
        
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
        
        let data = try await loadData(for: request)
        
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
        
        let data = try await loadData(for: request)
        
        return try parseNeteaseSearchResponse(data: data)
    }
    
    private func playURLGDStudio(songID: String) async throws -> URL {
        let urlString = "https://music-api.gdstudio.xyz/api/song/enhance/player/url?ids=[\(songID)]&br=320000"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let data = try await loadData(for: request)
        
        return try parseNeteasePlayURLResponse(data: data)
    }
    
    private func lyricGDStudio(songID: String) async throws -> String {
        let urlString = "https://music-api.gdstudio.xyz/api/song/lyric?id=\(songID)&lv=-1&tv=-1"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let data = try await loadData(for: request)
        
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
        
        let data = try await loadData(for: request)
        
        return try parseNeteaseSearchResponse(data: data)
    }
    
    private func playURLCustom(songID: String, apiBase: String) async throws -> URL {
        let urlString = "\(apiBase)/api/song/enhance/player/url?ids=[\(songID)]&br=320000"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let data = try await loadData(for: request)
        
        return try parseNeteasePlayURLResponse(data: data)
    }
    
    private func lyricCustom(songID: String, apiBase: String) async throws -> String {
        let urlString = "\(apiBase)/api/song/lyric?id=\(songID)&lv=-1&tv=-1"
        
        guard let url = URL(string: urlString) else {
            throw OnlineMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let data = try await loadData(for: request)
        
        return try parseNeteaseLyricResponse(data: data)
    }
    
    // MARK: - Network helpers

    private func loadData(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            return data
        } catch is CancellationError {
            throw OnlineMusicError.cancelled
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw OnlineMusicError.networkUnavailable
            case .timedOut:
                throw OnlineMusicError.timeout
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw OnlineMusicError.providerUnavailable
            case .cancelled:
                throw OnlineMusicError.cancelled
            default:
                throw OnlineMusicError.networkError(error)
            }
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw OnlineMusicError.proxyRequired
        case 404:
            throw OnlineMusicError.notFound
        case 429:
            throw OnlineMusicError.rateLimited
        case 500...599:
            throw OnlineMusicError.providerUnavailable
        default:
            throw OnlineMusicError.httpStatus(httpResponse.statusCode)
        }
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

public enum OnlineMusicProvider: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case netease
    case gdstudio
    case custom  // 自定义 API（URL 存在 OnlineSourceConfig.onlineMusicBaseURL）
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .netease: return "网易云音乐"
        case .gdstudio: return "GD Studio"
        case .custom: return "自定义"
        }
    }
    
    /// 转换为 OnlineSourceKind（用于存储配置）
    public func toOnlineSourceKind() -> OnlineSourceKind {
        switch self {
        case .netease: return .onlineMusicNetease
        case .gdstudio: return .onlineMusicGDStudio
        case .custom: return .onlineMusicCustom
        }
    }
}

// MARK: - 错误

public enum OnlineMusicError: LocalizedError {
    case invalidURL
    case parseError
    case noPlayURL
    case networkUnavailable
    case timeout
    case providerUnavailable
    case rateLimited
    case notFound
    case proxyRequired
    case cancelled
    case httpStatus(Int)
    case networkError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 API 地址"
        case .parseError:
            return "在线音乐接口返回格式异常，请换源或稍后再试。"
        case .noPlayURL:
            return "这首歌暂时没有可播放地址，试试其他结果。"
        case .networkUnavailable:
            return "网络连接不可用，请检查网络后重试。"
        case .timeout:
            return "在线音乐请求超时，请稍后重试。"
        case .providerUnavailable:
            return "在线音乐源暂时不可用，请稍后重试或切换音乐源。"
        case .rateLimited:
            return "请求过于频繁，在线音乐源正在限流，请稍后再试。"
        case .notFound:
            return "没有找到相关在线音乐资源。"
        case .proxyRequired:
            return "在线音乐源拒绝了请求，可能需要检查代理或更换音乐源。"
        case .cancelled:
            return "请求已取消。"
        case .httpStatus(let status):
            return "在线音乐源返回 HTTP \(status)。"
        case .networkError(let error):
            return "网络错误：\(error.localizedDescription)"
        }
    }
}
