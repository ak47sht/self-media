import Foundation
import MediaLibCore

/// 工厂方法：将 IPTV 频道和 VOD 视频转换为 MediaItem 以便播放
enum MediaItemFactory {
    
    /// 从 IPTV 频道创建 MediaItem
    /// - Parameters:
    ///   - channel: IPTV 频道
    ///   - urlIndex: 使用的线路索引（默认 0）
    /// - Returns: 可播放的 MediaItem
    static func makeMediaItem(from channel: IPTVChannel, urlIndex: Int = 0) -> MediaItem? {
        guard urlIndex < channel.urls.count else { return nil }
        let playURL = channel.urls[urlIndex]
        
        DebugLog.log("MediaItemFactory", "创建 IPTV MediaItem: \(channel.name) (URL index: \(urlIndex)/\(channel.urls.count))")
        
        return MediaItem(
            id: "\(channel.sourceID)_\(channel.channelID)_\(urlIndex)",
            type: .movie,  // IPTV 直播使用 movie 类型
            title: channel.name,
            originalTitle: nil,
            artist: nil,
            album: channel.groupTitle,
            trackNumber: nil,
            year: nil,
            overview: "IPTV 直播频道",
            posterPath: channel.logo,
            backdropPath: nil,
            rating: nil,
            userRating: nil,
            runtime: nil,
            sourcePath: playURL,
            parentID: channel.sourceID,
            seasonNumber: nil,
            episodeNumber: nil,
            filePath: playURL,
            fileSize: nil,
            videoCodec: nil,
            audioCodec: nil,
            resolution: nil,
            videoBitrate: nil,
            duration: nil,
            loudnessTrackGainDB: nil,
            loudnessAlbumGainDB: nil,
            loudnessTrackPeak: nil,
            loudnessAlbumPeak: nil,
            playCount: 0,
            playPosition: 0,
            playProgress: 0,
            watched: false,
            favorite: false,
            watchlist: false,
            externalID: nil,
            metadataProvider: nil,
            collectionTitle: channel.groupTitle,
            createdAt: channel.updatedAt ?? Date(),
            updatedAt: channel.updatedAt ?? Date(),
            lastPlayedAt: nil,
            genre: channel.groupTitle
        )
    }
    
    /// 从 VOD 视频剧集创建 MediaItem
    /// - Parameters:
    ///   - video: VOD 视频
    ///   - episode: 剧集信息
    /// - Returns: 可播放的 MediaItem
    static func makeMediaItem(from video: VODVideo, episode: VODEpisode, sourceName: String? = nil) -> MediaItem {
        DebugLog.log("MediaItemFactory", "创建 VOD MediaItem: \(video.name) - \(episode.name)")
        DebugLog.log("MediaItemFactory", "  URL: \(episode.url)")
        
        return MediaItem(
            id: "\(video.sourceID)_\(video.vodID)_\(episode.name)",
            type: .episode,  // VOD 剧集使用 episode 类型
            title: "\(video.name) - \(episode.name)",
            originalTitle: video.name,
            artist: video.director,
            album: video.type,
            trackNumber: nil,
            year: video.year.flatMap { Int($0) },
            overview: video.content,
            posterPath: video.pic,
            backdropPath: nil,
            rating: nil,
            userRating: nil,
            runtime: nil,
            sourcePath: episode.url,
            parentID: video.vodID,
            seasonNumber: nil,
            episodeNumber: nil,
            filePath: episode.url,
            fileSize: nil,
            videoCodec: nil,
            audioCodec: nil,
            resolution: nil,
            videoBitrate: nil,
            duration: nil,
            loudnessTrackGainDB: nil,
            loudnessAlbumGainDB: nil,
            loudnessTrackPeak: nil,
            loudnessAlbumPeak: nil,
            playCount: 0,
            playPosition: 0,
            playProgress: 0,
            watched: false,
            favorite: false,
            watchlist: false,
            externalID: nil,
            metadataProvider: sourceName,
            collectionTitle: video.type,
            createdAt: video.updatedAt ?? Date(),
            updatedAt: video.updatedAt ?? Date(),
            lastPlayedAt: nil,
            genre: video.type
        )
    }
}
