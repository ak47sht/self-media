import Foundation
import MediaLibCore

/// 播放历史管理器 - 记录 IPTV 和 VOD 播放历史
actor PlaybackHistoryManager {
    private let database: DatabaseManager
    
    init(database: DatabaseManager) {
        self.database = database
    }
    
    // MARK: - IPTV History
    
    /// 记录 IPTV 频道播放
    func recordIPTVPlayback(channelID: String, sourceID: String, channelName: String) async throws {
        let sql = """
        INSERT OR REPLACE INTO iptv_playback_history (
            channel_id, source_id, channel_name, last_played_at, play_count
        ) VALUES (
            ?, ?, ?, ?,
            COALESCE((SELECT play_count FROM iptv_playback_history WHERE channel_id = ? AND source_id = ?), 0) + 1
        )
        """
        
        let now = Date()
        try await database.execute(
            sql,
            bindings: [
                .text(channelID),
                .text(sourceID),
                .text(channelName),
                .int(Int64(now.timeIntervalSince1970)),
                .text(channelID),
                .text(sourceID)
            ]
        )
    }
    
    /// 获取最近播放的 IPTV 频道
    func getRecentIPTVChannels(limit: Int = 20) async throws -> [IPTVPlaybackRecord] {
        let sql = """
        SELECT channel_id, source_id, channel_name, last_played_at, play_count
        FROM iptv_playback_history
        ORDER BY last_played_at DESC
        LIMIT ?
        """
        
        let rows = try await database.query(sql, bindings: [.int(Int64(limit))])
        return rows.compactMap { row in
            guard let channelID = row["channel_id"]?.textValue,
                  let sourceID = row["source_id"]?.textValue,
                  let channelName = row["channel_name"]?.textValue,
                  let lastPlayedTimestamp = row["last_played_at"]?.intValue,
                  let playCount = row["play_count"]?.intValue else {
                return nil
            }
            
            return IPTVPlaybackRecord(
                channelID: channelID,
                sourceID: sourceID,
                channelName: channelName,
                lastPlayedAt: Date(timeIntervalSince1970: TimeInterval(lastPlayedTimestamp)),
                playCount: Int(playCount)
            )
        }
    }
    
    // MARK: - VOD History
    
    /// 记录 VOD 视频播放进度
    func recordVODPlayback(
        vodID: String,
        sourceID: String,
        episodeName: String,
        position: TimeInterval,
        duration: TimeInterval
    ) async throws {
        let progress = duration > 0 ? position / duration : 0
        let isWatched = progress > 0.9 // 播放超过 90% 认为已看完
        
        let sql = """
        INSERT OR REPLACE INTO vod_playback_history (
            vod_id, source_id, episode_name, position, duration, progress,
            is_watched, last_played_at, play_count
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?,
            COALESCE((SELECT play_count FROM vod_playback_history WHERE vod_id = ? AND source_id = ? AND episode_name = ?), 0) + 1
        )
        """
        
        let now = Date()
        try await database.execute(
            sql,
            bindings: [
                .text(vodID),
                .text(sourceID),
                .text(episodeName),
                .real(position),
                .real(duration),
                .real(progress),
                .int(isWatched ? 1 : 0),
                .int(Int64(now.timeIntervalSince1970)),
                .text(vodID),
                .text(sourceID),
                .text(episodeName)
            ]
        )
    }
    
    /// 获取 VOD 视频的播放进度
    func getVODPlaybackProgress(vodID: String, sourceID: String, episodeName: String) async throws -> VODPlaybackRecord? {
        let sql = """
        SELECT vod_id, source_id, episode_name, position, duration, progress,
               is_watched, last_played_at, play_count
        FROM vod_playback_history
        WHERE vod_id = ? AND source_id = ? AND episode_name = ?
        """
        
        let rows = try await database.query(
            sql,
            bindings: [.text(vodID), .text(sourceID), .text(episodeName)]
        )
        
        guard let row = rows.first else { return nil }
        return parseVODPlaybackRecord(from: row)
    }
    
    /// 获取最近播放的 VOD 视频
    func getRecentVODVideos(limit: Int = 20) async throws -> [VODPlaybackRecord] {
        let sql = """
        SELECT vod_id, source_id, episode_name, position, duration, progress,
               is_watched, last_played_at, play_count
        FROM vod_playback_history
        ORDER BY last_played_at DESC
        LIMIT ?
        """
        
        let rows = try await database.query(sql, bindings: [.int(Int64(limit))])
        return rows.compactMap { parseVODPlaybackRecord(from: $0) }
    }
    
    /// 获取未看完的 VOD 视频（断点续播）
    func getUnfinishedVODVideos(limit: Int = 20) async throws -> [VODPlaybackRecord] {
        let sql = """
        SELECT vod_id, source_id, episode_name, position, duration, progress,
               is_watched, last_played_at, play_count
        FROM vod_playback_history
        WHERE is_watched = 0 AND progress > 0.05
        ORDER BY last_played_at DESC
        LIMIT ?
        """
        
        let rows = try await database.query(sql, bindings: [.int(Int64(limit))])
        return rows.compactMap { parseVODPlaybackRecord(from: $0) }
    }
    
    // MARK: - Private Helpers
    
    private func parseVODPlaybackRecord(from row: [String: SQLiteValue]) -> VODPlaybackRecord? {
        guard let vodID = row["vod_id"]?.textValue,
              let sourceID = row["source_id"]?.textValue,
              let episodeName = row["episode_name"]?.textValue,
              let position = row["position"]?.realValue,
              let duration = row["duration"]?.realValue,
              let progress = row["progress"]?.realValue,
              let isWatched = row["is_watched"]?.intValue,
              let lastPlayedTimestamp = row["last_played_at"]?.intValue,
              let playCount = row["play_count"]?.intValue else {
            return nil
        }
        
        return VODPlaybackRecord(
            vodID: vodID,
            sourceID: sourceID,
            episodeName: episodeName,
            position: position,
            duration: duration,
            progress: progress,
            isWatched: isWatched != 0,
            lastPlayedAt: Date(timeIntervalSince1970: TimeInterval(lastPlayedTimestamp)),
            playCount: Int(playCount)
        )
    }
}

// MARK: - Data Models

struct IPTVPlaybackRecord: Identifiable {
    let channelID: String
    let sourceID: String
    let channelName: String
    let lastPlayedAt: Date
    let playCount: Int
    
    var id: String { "\(sourceID)_\(channelID)" }
}

struct VODPlaybackRecord: Identifiable {
    let vodID: String
    let sourceID: String
    let episodeName: String
    let position: TimeInterval
    let duration: TimeInterval
    let progress: Double
    let isWatched: Bool
    let lastPlayedAt: Date
    let playCount: Int
    
    var id: String { "\(sourceID)_\(vodID)_\(episodeName)" }
}
