import Foundation
import MediaLibCore

/// IPTV 频道管理服务
@MainActor
public class IPTVService {
    private let db: DatabaseManager
    
    public init(db: DatabaseManager) {
        self.db = db
    }
    
    /// 拉取 M3U 订阅并更新缓存
    public func fetchAndCacheChannels(from source: MediaSource, forceRefresh: Bool = false) async throws -> [IPTVChannel] {
        guard source.sourceKind == .iptv else {
            throw IPTVServiceError.invalidSourceType
        }
        
        guard let config = source.onlineConfig, case .iptv = config.kind else {
            throw IPTVServiceError.missingConfiguration
        }
        
        guard let subscriptionURL = config.subscriptionURL ?? config.apiBase else {
            throw IPTVServiceError.missingSubscriptionURL
        }
        
        // 拉取并解析 M3U
        let channels = try await M3UParser.fetch(from: subscriptionURL, sourceID: source.id)
        
        // 聚合同名频道的多个 URL（多线路支持）
        let aggregated = aggregateChannels(channels)
        
        // 写入缓存
        try saveChannelsToCache(aggregated, sourceID: source.id)
        
        return aggregated
    }
    
    /// 从缓存加载频道列表
    public func loadCachedChannels(sourceID: String) throws -> [IPTVChannel] {
        let rows = try db.query(
            """
            SELECT channel_id, name, group_title, logo, urls_json, updated_at
            FROM iptv_channels_cache
            WHERE source_id = ?
            ORDER BY group_title, name
            """,
            bindings: [.text(sourceID)]
        ) { (rs: SQLiteRow) -> IPTVChannel? in
            guard let channelID = rs.string(0),
                  let name = rs.string(1) else {
                return nil
            }
            
            let groupTitle = rs.string(2)
            let logo = rs.string(3)
            let urlsJSON = rs.string(4) ?? "[]"
            let updatedAtString = rs.string(5)
            
            // 解析 URLs JSON
            let urls: [String]
            if let data = urlsJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                urls = decoded
            } else {
                urls = []
            }
            
            // 解析更新时间
            let updatedAt: Date?
            if let timeString = updatedAtString {
                updatedAt = ISO8601DateFormatter().date(from: timeString)
            } else {
                updatedAt = nil
            }
            
            return IPTVChannel(
                sourceID: sourceID,
                channelID: channelID,
                name: name,
                urls: urls,
                groupTitle: groupTitle,
                logo: logo,
                updatedAt: updatedAt
            )
        }
        
        return rows.compactMap { $0 }
    }
    
    /// 聚合同名频道的多个 URL（支持多线路）
    private func aggregateChannels(_ channels: [IPTVChannel]) -> [IPTVChannel] {
        var grouped: [String: [IPTVChannel]] = [:]
        
        for channel in channels {
            let key = channel.channelID
            grouped[key, default: []].append(channel)
        }
        
        return grouped.values.map { group in
            let first = group[0]
            let allURLs = group.flatMap { $0.urls }
            
            return IPTVChannel(
                sourceID: first.sourceID,
                channelID: first.channelID,
                name: first.name,
                urls: allURLs,
                groupTitle: first.groupTitle,
                logo: first.logo,
                updatedAt: Date()
            )
        }
    }
    
    /// 将频道列表写入缓存
    private func saveChannelsToCache(_ channels: [IPTVChannel], sourceID: String) throws {
        // 清空旧缓存
        try db.execute("DELETE FROM iptv_channels_cache WHERE source_id = ?", bindings: [.text(sourceID)])
        
        // 批量插入
        for channel in channels {
            let urlsData = try JSONEncoder().encode(channel.urls)
            let urlsJSON = String(data: urlsData, encoding: .utf8) ?? "[]"
            let updatedAt = ISO8601DateFormatter().string(from: channel.updatedAt ?? Date())
            
            try db.execute(
                """
                INSERT INTO iptv_channels_cache (source_id, channel_id, name, group_title, logo, urls_json, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(sourceID),
                    .text(channel.channelID),
                    .text(channel.name),
                    channel.groupTitle.map { .text($0) } ?? .null,
                    channel.logo.map { .text($0) } ?? .null,
                    .text(urlsJSON),
                    .text(updatedAt)
                ]
            )
        }
    }
}

/// IPTV 服务错误
public enum IPTVServiceError: LocalizedError {
    case invalidSourceType
    case missingConfiguration
    case missingSubscriptionURL
    
    public var errorDescription: String? {
        switch self {
        case .invalidSourceType:
            return "媒体源类型不是 IPTV"
        case .missingConfiguration:
            return "缺少 IPTV 配置"
        case .missingSubscriptionURL:
            return "缺少订阅地址"
        }
    }
}
