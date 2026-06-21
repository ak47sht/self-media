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
    public let provider: OnlineMusicProvider?
    
    public init(id: String, name: String, artist: String, album: String?, duration: TimeInterval, coverURL: String?, provider: OnlineMusicProvider? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.duration = duration
        self.coverURL = coverURL
        self.provider = provider
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
    private var tabosBaseURL: String = "https://ios.25pan.com"
    private var preferredQuality: String = "320k"
    
    // Search result cache (30-minute TTL, max 50 entries)
    private let searchCache: NSCache<NSString, CachedSearchResult> = {
        let cache = NSCache<NSString, CachedSearchResult>()
        cache.countLimit = 50
        return cache
    }()
    private final class CachedSearchResult: NSObject {
        let songs: [OnlineMusicTrack]
        let timestamp: Date
        init(songs: [OnlineMusicTrack], timestamp: Date) {
            self.songs = songs
            self.timestamp = timestamp
        }
    }
    
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

    public func setTabosBaseURL(_ url: String) {
        self.tabosBaseURL = url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "https://ios.25pan.com" : url
    }

    public func setPreferredQuality(_ quality: String?) {
        let trimmed = quality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.preferredQuality = trimmed.isEmpty ? "320k" : trimmed
    }
    
    // MARK: - 兼容旧 API 的方法
    
    /// 搜索音乐（兼容旧 API 签名）
    public func search(query: String, neteaseAPI: String?, gdstudioAPI: String?, tabosAPI: String? = nil) async throws -> SearchResult {
        // 优先使用 neteaseAPI，其次 gdstudioAPI，最后官方源
        let provider: OnlineMusicProvider
        if let apiBase = tabosAPI {
            setTabosBaseURL(apiBase)
            provider = .tabos
        } else if let apiBase = neteaseAPI {
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
    public func playURL(song: Song, neteaseAPI: String?, gdstudioAPI: String?, tabosAPI: String? = nil, quality: String? = nil) async throws -> (url: String, lyric: String?) {
        // 播放必须跟随歌曲自身来源，避免配置了 Tabos 后把网易/GD 的 song id 串到 Tabos 解析。
        let provider: OnlineMusicProvider
        setPreferredQuality(quality)
        if let songProvider = song.provider {
            provider = songProvider
            switch songProvider {
            case .tabos:
                setTabosBaseURL(tabosAPI ?? "https://ios.25pan.com")
            case .custom:
                customBaseURL = neteaseAPI ?? gdstudioAPI ?? customBaseURL
            case .gdstudio:
                customBaseURL = gdstudioAPI ?? customBaseURL
            case .netease:
                customBaseURL = neteaseAPI ?? customBaseURL
            }
        } else if song.id.contains(":"), let apiBase = tabosAPI {
            setTabosBaseURL(apiBase)
            provider = .tabos
        } else if let apiBase = neteaseAPI {
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
    
    /// 搜索音乐（支持多源 fallback，带 30 分钟缓存）
    public func search(query: String, provider: OnlineMusicProvider) async throws -> [OnlineMusicTrack] {
        // Include base URL in cache key for .tabos/.custom (different endpoints may return different results)
        var cacheKeyStr = "\(provider.rawValue):\(query.lowercased().trimmingCharacters(in: .whitespaces))"
        if provider == .tabos { cacheKeyStr += ":\(tabosBaseURL)" }
        if provider == .custom { cacheKeyStr += ":\(customBaseURL)" }
        let cacheKey = cacheKeyStr as NSString
        
        // Check cache first (30-minute TTL)
        if let cached = searchCache.object(forKey: cacheKey),
           Date().timeIntervalSince(cached.timestamp) < 1800 {
            return cached.songs
        }
        
        let results: [OnlineMusicTrack]
        switch provider {
        case .netease:
            results = try await searchNetease(query: query)
        case .gdstudio:
            results = try await searchGDStudio(query: query)
        case .tabos:
            results = try await searchTabos(query: query, apiBase: tabosBaseURL)
        case .custom:
            results = try await searchCustom(query: query, apiBase: customBaseURL)
        }
        
        // Store in cache
        searchCache.setObject(CachedSearchResult(songs: results, timestamp: Date()), forKey: cacheKey)
        return results
    }
    
    // MARK: - 播放地址
    
    /// 获取播放地址
    public func playURL(songID: String, provider: OnlineMusicProvider) async throws -> URL {
        switch provider {
        case .netease:
            return try await playURLNetease(songID: songID)
        case .gdstudio:
            return try await playURLGDStudio(songID: songID)
        case .tabos:
            return try await playURLTabos(songID: songID, apiBase: tabosBaseURL, quality: preferredQuality)
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
        case .tabos:
            return try await lyricTabos(songID: songID, apiBase: tabosBaseURL)
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
                coverURL: coverURL,
                provider: .netease
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
        
        return try parseNeteaseSearchResponse(data: data, provider: .gdstudio)
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
        
        return try parseNeteaseSearchResponse(data: data, provider: .custom)
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

    // MARK: - Tabos / 25pan 聚合音乐 API

    private func tabosMusicBase(_ apiBase: String) -> String {
        let trimmed = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (trimmed.isEmpty ? "https://ios.25pan.com" : trimmed)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.hasSuffix("/api/music") { return base }
        return "\(base)/api/music"
    }

    private func searchTabos(query: String, apiBase: String) async throws -> [OnlineMusicTrack] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(tabosMusicBase(apiBase))/search/songs?q=\(encodedQuery)&source=all&page=1&page_size=30"
        guard let url = URL(string: urlString) else { throw OnlineMusicError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://ios.25pan.com/music", forHTTPHeaderField: "Referer")

        let data = try await loadData(for: request)
        return try parseTabosSearchResponse(data: data)
    }

    private func playURLTabos(songID: String, apiBase: String, quality: String) async throws -> URL {
        let components = splitTabosSongID(songID)
        let encodedSource = components.source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? components.source
        let encodedID = components.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? components.id
        let encodedQuality = quality.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? quality
        let urlString = "\(tabosMusicBase(apiBase))/songs/url/\(encodedSource)/\(encodedID)?quality=\(encodedQuality)"
        guard let url = URL(string: urlString) else { throw OnlineMusicError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://ios.25pan.com/music", forHTTPHeaderField: "Referer")

        let data = try await loadData(for: request)
        return try parseTabosPlayURLResponse(data: data)
    }

    private func lyricTabos(songID: String, apiBase: String) async throws -> String {
        let components = splitTabosSongID(songID)
        let encodedSource = components.source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? components.source
        let encodedID = components.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? components.id
        let urlString = "\(tabosMusicBase(apiBase))/lyrics/discover?id=\(encodedID)&source=\(encodedSource)&need_word=false"
        guard let url = URL(string: urlString) else { throw OnlineMusicError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://ios.25pan.com/music", forHTTPHeaderField: "Referer")

        let data = try await loadData(for: request)
        return try parseTabosLyricResponse(data: data)
    }

    private func splitTabosSongID(_ songID: String) -> (source: String, id: String) {
        let parts = songID.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            return (parts[0], parts[1])
        }
        return ("kuwo", songID)
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
    
    private func parseNeteaseSearchResponse(data: Data, provider: OnlineMusicProvider = .netease) throws -> [OnlineMusicTrack] {
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
                coverURL: coverURL,
                provider: provider
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

    private func parseTabosSearchResponse(data: Data) throws -> [OnlineMusicTrack] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? Int,
              code == 0,
              let payload = json["data"] as? [String: Any] else {
            throw OnlineMusicError.parseError
        }
        let songs = (payload["list"] as? [[String: Any]]) ?? (payload["songs"] as? [[String: Any]]) ?? []

        return songs.compactMap { song in
            let source = (song["source"] as? String) ?? (song["provider"] as? String) ?? "kuwo"
            let rawID = String(describing: song["id"] ?? song["songId"] ?? song["song_id"] ?? "")
            guard !rawID.isEmpty,
                  let name = song["name"] as? String ?? song["title"] as? String else {
                return nil
            }

            let artists: String
            if let artistArray = song["artists"] as? [[String: Any]] {
                artists = artistArray.compactMap { $0["name"] as? String }.joined(separator: ", ")
            } else {
                artists = song["artist"] as? String ?? "Unknown"
            }
            let albumInfo = song["album"] as? [String: Any]
            let album = albumInfo?["name"] as? String ?? song["album"] as? String
            let durationMs = song["durationMs"] as? Double ?? song["duration_ms"] as? Double ?? 0
            let duration = durationMs > 0 ? durationMs / 1000.0 : (song["duration"] as? Double ?? 0)
            let coverURL = song["cover"] as? String ?? albumInfo?["cover"] as? String

            return OnlineMusicTrack(
                id: "\(source):\(rawID)",
                name: name,
                artist: artists.isEmpty ? "Unknown" : artists,
                album: album,
                duration: duration,
                coverURL: coverURL,
                provider: .tabos
            )
        }
    }

    private func parseTabosPlayURLResponse(data: Data) throws -> URL {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? Int,
              code == 0,
              let payload = json["data"] as? [String: Any],
              let urlString = payload["url"] as? String,
              let playURL = URL(string: urlString) else {
            throw OnlineMusicError.noPlayURL
        }
        return playURL
    }

    private func parseTabosLyricResponse(data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? Int,
              code == 0 else {
            return ""
        }
        if let payload = json["data"] as? [String: Any] {
            return payload["lyric"] as? String
                ?? payload["lyricText"] as? String
                ?? payload["lrc"] as? String
                ?? ""
        }
        return json["data"] as? String ?? ""
    }
}

// MARK: - 在线音乐提供商

public enum OnlineMusicProvider: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case netease
    case gdstudio
    case tabos
    case custom  // 自定义 API（URL 存在 OnlineSourceConfig.onlineMusicBaseURL）
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .netease: return "网易云音乐"
        case .gdstudio: return "GD Studio"
        case .tabos: return "Tabos / 25pan"
        case .custom: return "自定义"
        }
    }
    
    /// 转换为 OnlineSourceKind（用于存储配置）
    public func toOnlineSourceKind() -> OnlineSourceKind {
        switch self {
        case .netease: return .onlineMusicNetease
        case .gdstudio: return .onlineMusicGDStudio
        case .tabos: return .onlineMusicTabos
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
