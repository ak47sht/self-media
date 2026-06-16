import Foundation
import MediaLibCore

/// VOD 视频点播服务
/// 支持 CMS JSON API (苹果CMS/飞飞CMS 格式)
public class VODService {
    private let db: DatabaseManager
    
    public init(db: DatabaseManager) {
        self.db = db
    }
    
    /// 从 CMS API 拉取视频列表并缓存
    /// - Parameters:
    ///   - source: VOD 源
    ///   - page: 页码（从1开始）
    ///   - keyword: 搜索关键词（可选）
    ///   - typeID: 分类ID（可选）
    /// - Returns: 视频列表
    public func fetchVideos(
        from source: MediaSource,
        page: Int = 1,
        keyword: String? = nil,
        typeID: String? = nil
    ) async throws -> [VODVideo] {
        guard source.sourceKind == .vod else {
            throw VODServiceError.invalidSourceType
        }
        
        guard let config = source.onlineConfig,
              let baseURL = config.apiBase else {
            throw VODServiceError.missingConfiguration
        }
        
        // 构建 URL
        var urlComponents = URLComponents(string: baseURL)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "pg", value: String(page))
        ]
        
        if let keyword = keyword {
            queryItems.append(URLQueryItem(name: "wd", value: keyword))
        }
        
        if let typeID = typeID {
            queryItems.append(URLQueryItem(name: "t", value: typeID))
        }
        
        urlComponents?.queryItems = queryItems
        
        guard let url = urlComponents?.url else {
            throw VODServiceError.invalidURL
        }
        
        // 发起请求
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["list"] as? [[String: Any]] else {
            throw VODServiceError.parseError
        }
        
        // 解析视频列表
        let videos = list.compactMap { VODVideo.parseFromCMS(json: $0, sourceID: source.id) }
        
        // 缓存到数据库
        try cacheVideos(videos)
        
        return videos
    }
    
    /// 拉取并缓存视频（便捷方法）
    public func fetchAndCacheVideos(
        from source: MediaSource,
        page: Int = 1,
        pageSize: Int = 100
    ) async throws -> [VODVideo] {
        return try await fetchVideos(from: source, page: page)
    }
    
    /// 缓存视频列表到数据库
    private func cacheVideos(_ videos: [VODVideo]) throws {
        try db.transaction {
            for video in videos {
                // 序列化 playURLs 为 JSON
                let playURLsData = try JSONEncoder().encode(video.playURLs)
                let playURLsJSON = String(data: playURLsData, encoding: .utf8) ?? "[]"
                
                // 插入或更新
                try db.execute(
                    """
                    INSERT OR REPLACE INTO vod_videos_cache (
                        source_id, vod_id, name, type, year, area, lang, pic,
                        actors, director, content, play_urls_json, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    bindings: [
                        .text(video.sourceID),
                        .text(video.vodID),
                        .text(video.name),
                        .text(video.type ?? ""),
                        .text(video.year ?? ""),
                        .text(video.area ?? ""),
                        .text(video.lang ?? ""),
                        .text(video.pic ?? ""),
                        .text(video.actors ?? ""),
                        .text(video.director ?? ""),
                        .text(video.content ?? ""),
                        .text(playURLsJSON),
                        .text(ISO8601DateFormatter().string(from: video.updatedAt ?? Date()))
                    ]
                )
            }
        }
    }
    
    /// 从缓存加载视频列表
    public func loadCachedVideos(sourceID: String, type: String? = nil, limit: Int = 100) throws -> [VODVideo] {
        var sql = """
            SELECT source_id, vod_id, name, type, year, area, lang, pic,
                   actors, director, content, play_urls_json, updated_at
            FROM vod_videos_cache
            WHERE source_id = ?
        """
        
        var bindings: [SQLiteValue] = [.text(sourceID)]
        
        if let type = type {
            sql += " AND type = ?"
            bindings.append(.text(type))
        }
        
        sql += " ORDER BY updated_at DESC LIMIT ?"
        bindings.append(.int(Int64(limit)))
        
        return try db.query(sql, bindings: bindings) { (rs: SQLiteRow) -> VODVideo? in
            guard let sourceID = rs.string(0),
                  let vodID = rs.string(1),
                  let name = rs.string(2) else {
                return nil
            }
            
            let type = rs.string(3)
            let year = rs.string(4)
            let area = rs.string(5)
            let lang = rs.string(6)
            let pic = rs.string(7)
            let actors = rs.string(8)
            let director = rs.string(9)
            let content = rs.string(10)
            let playURLsJSON = rs.string(11) ?? "[]"
            let updatedAtString = rs.string(12)
            
            // 解析 play_urls
            let playURLs: [VODPlayLine]
            if let data = playURLsJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([VODPlayLine].self, from: data) {
                playURLs = decoded
            } else {
                playURLs = []
            }
            
            // 解析更新时间
            let updatedAt: Date?
            if let timeString = updatedAtString {
                updatedAt = ISO8601DateFormatter().date(from: timeString)
            } else {
                updatedAt = nil
            }
            
            return VODVideo(
                sourceID: sourceID,
                vodID: vodID,
                name: name,
                type: type,
                year: year,
                area: area,
                lang: lang,
                pic: pic,
                actors: actors,
                director: director,
                content: content,
                playURLs: playURLs,
                updatedAt: updatedAt
            )
        }.compactMap { $0 }
    }
}

/// VOD 服务错误
public enum VODServiceError: LocalizedError {
    case invalidSourceType
    case missingConfiguration
    case invalidURL
    case parseError
    
    public var errorDescription: String? {
        switch self {
        case .invalidSourceType:
            return "源类型不正确，需要 VOD 源"
        case .missingConfiguration:
            return "缺少 VOD 源配置"
        case .invalidURL:
            return "无效的 VOD API 地址"
        case .parseError:
            return "解析 VOD 数据失败"
        }
    }
}
