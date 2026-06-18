import CFNetwork
import Foundation
import MediaLibCore

/// VOD 分页结果
public struct VODPagedResult: Sendable {
    public let videos: [VODVideo]
    public let page: Int
    public let pageCount: Int
    public let total: Int

    public var hasMore: Bool { page < pageCount }
}

/// VOD 视频点播服务
/// 支持 CMS JSON API (苹果CMS/飞飞CMS 格式)
public class VODService {
    private let db: DatabaseManager
    private let directSession: URLSession
    private let systemSession: URLSession

    public init(db: DatabaseManager) {
        self.db = db
        self.directSession = Self.makeDirectSession()
        self.systemSession = .shared
    }

    private static func makeDirectSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 0,
            kCFNetworkProxiesHTTPSEnable as String: 0,
            kCFNetworkProxiesSOCKSEnable as String: 0
        ]
        return URLSession(configuration: configuration)
    }

    private func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await directSession.data(for: request)
        } catch {
            DebugLog.log("VODService", "直连请求失败，尝试系统网络配置: \(error.localizedDescription)")
            return try await systemSession.data(for: request)
        }
    }

    /// 从 CMS API 拉取视频列表并缓存
    /// - Parameters:
    ///   - source: VOD 源
    ///   - page: 页码（从1开始）
    ///   - keyword: 搜索关键词（可选）
    ///   - typeID: 分类ID（可选）
    /// - Returns: 分页结果
    public func fetchVideos(
        from source: MediaSource,
        page: Int = 1,
        keyword: String? = nil,
        typeID: String? = nil
    ) async throws -> VODPagedResult {
        guard source.sourceKind == .vod else {
            throw VODServiceError.invalidSourceType
        }

        guard let config = source.onlineConfig,
              let baseURL = config.apiBase else {
            throw VODServiceError.missingConfiguration
        }

        // 构建 URL
        guard let url = cmsURL(baseURL, adding: [
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "pg", value: String(page))
        ] + (keyword.map { [URLQueryItem(name: "wd", value: $0)] } ?? []) + (typeID.map { [URLQueryItem(name: "t", value: $0)] } ?? [])) else {
            throw VODServiceError.invalidURL
        }

        DebugLog.log("VODService", "请求 VOD API: \(url.absoluteString)")

        // 发起请求（带 User-Agent 避免 403）
        var request = URLRequest(url: url)
        request.setValue("MediaLib/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let startTime = Date()
        let (data, response) = try await loadData(for: request)
        let elapsed = Date().timeIntervalSince(startTime)
        try validateHTTPResponse(response)

        DebugLog.log("VODService", "API 响应耗时: \(String(format: "%.2f", elapsed))s, 数据大小: \(data.count) bytes")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            DebugLog.log("VODService", "❌ JSON 解析失败")
            throw VODServiceError.parseError
        }

        guard let list = json["list"] as? [[String: Any]] else {
            DebugLog.log("VODService", "❌ 响应中缺少 'list' 字段")
            throw VODServiceError.parseError
        }

        // 解析分页信息
        let currentPage = json["page"] as? Int ?? page
        let pageCount = json["pagecount"] as? Int ?? 1
        let total = json["total"] as? Int ?? list.count

        DebugLog.log("VODService", "分页信息: 第 \(currentPage)/\(pageCount) 页, 总计 \(total) 条")

        // 解析视频列表
        let videos = list.compactMap { VODVideo.parseFromCMS(json: $0, sourceID: source.id) }
        DebugLog.log("VODService", "解析成功: \(videos.count) 个视频 (原始数据 \(list.count) 条)")

        // 缓存到数据库
        try cacheVideos(videos)

        return VODPagedResult(
            videos: videos,
            page: currentPage,
            pageCount: pageCount,
            total: total
        )
    }

    /// 获取 VOD 分类列表
    /// - Parameter source: VOD 源
    /// - Returns: 分类列表
    public func fetchCategories(from source: MediaSource) async throws -> [VODCategory] {
        guard source.sourceKind == .vod else {
            throw VODServiceError.invalidSourceType
        }

        guard let config = source.onlineConfig,
              let baseURL = config.apiBase else {
            throw VODServiceError.missingConfiguration
        }

        // 构建 URL (ac=list 返回分类列表)
        guard let url = cmsURL(baseURL, adding: [
            URLQueryItem(name: "ac", value: "list"),
            URLQueryItem(name: "pg", value: "1")
        ]) else {
            throw VODServiceError.invalidURL
        }

        DebugLog.log("VODService", "请求分类列表: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.setValue("MediaLib/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await loadData(for: request)
        try validateHTTPResponse(response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let classArray = json["class"] as? [[String: Any]] else {
            DebugLog.log("VODService", "❌ 分类列表解析失败")
            throw VODServiceError.parseError
        }

        let decoder = JSONDecoder()
        let categories = classArray.compactMap { dict -> VODCategory? in
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let category = try? decoder.decode(VODCategory.self, from: data) else {
                return nil
            }
            return category
        }

        DebugLog.log("VODService", "获取到 \(categories.count) 个分类")
        return categories
    }

    private func cmsURL(_ baseURL: String, adding newItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        let replacingNames = Set(newItems.map(\.name))
        let preservedItems = (components.queryItems ?? []).filter { !replacingNames.contains($0.name) }
        components.queryItems = preservedItems + newItems
        return components.url
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw VODServiceError.httpStatus(httpResponse.statusCode)
        }
    }

    /// 拉取并缓存视频（便捷方法）
    public func fetchAndCacheVideos(
        from source: MediaSource,
        page: Int = 1,
        pageSize: Int = 100
    ) async throws -> [VODVideo] {
        let result = try await fetchVideos(from: source, page: page)
        return result.videos
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
    public func loadCachedVideos(sourceID: String, type: String? = nil, limit: Int = 10000) throws -> [VODVideo] {
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
    case httpStatus(Int)

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
        case .httpStatus(let statusCode):
            return "VOD API 请求失败（HTTP \(statusCode)）"
        }
    }
}
