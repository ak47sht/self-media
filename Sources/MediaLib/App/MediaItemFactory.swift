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
        
        return MediaItem(
            id: "\(channel.sourceID)_\(channel.channelID)_\(urlIndex)",
            type: .video,
            title: channel.name,
            originalTitle: nil,
            artist: nil,
            album: channel.groupTitle,  // 分组名作为 "专辑"
            trackNumber: nil,
            year: nil,
            overview: "IPTV 直播频道",
            genre: channel.groupTitle,
            posterPath: channel.logo,
            backdropPath: nil,
            rating: nil,
            userRating: nil,
            runtime: nil,
            sourcePath: playURL,  // 播放地址
            parentID: channel.sourceID,
            seasonNumber: nil,
            episodeNumber: nil,
            filePath: playURL,
            fileSize: nil,
            videoCodec: nil,
            audioCodec: nil,
            resolution: nil,
            videoBitrate: nil,
            duration: nil,  // 直播流无固定时长
            loudnessTrackGainDB: nil,
            subtitleCodec: nil,
            contentAdvisory: nil,
            releaseDate: nil,
            addedAt: channel.updatedAt ?? Date(),
            lastPlayedAt: nil,
            playCount: 0,
            isWatched: false,
            sourceID: channel.sourceID,
            serverId: nil
        )
    }
    
    /// 从 VOD 视频剧集创建 MediaItem
    /// - Parameters:
    ///   - video: VOD 视频
    ///   - episode: 剧集信息
    /// - Returns: 可播放的 MediaItem
    static func makeMediaItem(from video: VODVideo, episode: VODEpisode) -> MediaItem {
        return MediaItem(
            id: "\(video.sourceID)_\(video.vodID)_\(episode.name)",
            type: .video,
            title: "\(video.name) - \(episode.name)",
            originalTitle: video.name,
            artist: video.director,
            album: video.type,  // 类型（电影/剧集/动漫等）
            trackNumber: nil,
            year: video.year.flatMap { Int($0) },
            overview: video.content,
            genre: video.type,
            posterPath: video.pic,
            backdropPath: nil,
            rating: nil,
            userRating: nil,
            runtime: nil,
            sourcePath: episode.url,  // 播放地址
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
            subtitleCodec: nil,
            contentAdvisory: nil,
            releaseDate: nil,
            addedAt: video.updatedAt ?? Date(),
            lastPlayedAt: nil,
            playCount: 0,
            isWatched: false,
            sourceID: video.sourceID,
            serverId: nil
        )
    }
}
