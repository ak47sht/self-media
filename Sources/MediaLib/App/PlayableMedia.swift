import Foundation
import MediaLibCore

/// 可播放媒体包装，支持多线路自动切换
public struct PlayableMedia {
    /// 主 MediaItem（用于播放器显示元数据）
    let primaryItem: MediaItem
    
    /// 所有可用的播放线路
    let routes: [PlayRoute]
    
    /// 当前使用的线路索引
    var currentRouteIndex: Int = 0
    
    /// 当前播放的 MediaItem
    var currentItem: MediaItem {
        guard currentRouteIndex < routes.count else { return primaryItem }
        let route = routes[currentRouteIndex]
        
        // 创建一个新的 MediaItem，复用元数据但使用当前线路的 URL
        return MediaItem(
            id: "\(primaryItem.id)_route_\(currentRouteIndex)",
            type: primaryItem.type,
            title: primaryItem.title,
            originalTitle: primaryItem.originalTitle,
            artist: primaryItem.artist,
            album: primaryItem.album,
            trackNumber: primaryItem.trackNumber,
            year: primaryItem.year,
            overview: primaryItem.overview,
            posterPath: primaryItem.posterPath,
            backdropPath: primaryItem.backdropPath,
            rating: primaryItem.rating,
            userRating: primaryItem.userRating,
            runtime: primaryItem.runtime,
            sourcePath: route.url,
            parentID: primaryItem.parentID,
            seasonNumber: primaryItem.seasonNumber,
            episodeNumber: primaryItem.episodeNumber,
            filePath: route.url,
            fileSize: primaryItem.fileSize,
            videoCodec: primaryItem.videoCodec,
            audioCodec: primaryItem.audioCodec,
            resolution: primaryItem.resolution,
            videoBitrate: primaryItem.videoBitrate,
            duration: primaryItem.duration,
            loudnessTrackGainDB: primaryItem.loudnessTrackGainDB,
            loudnessAlbumGainDB: primaryItem.loudnessAlbumGainDB,
            loudnessTrackPeak: primaryItem.loudnessTrackPeak,
            loudnessAlbumPeak: primaryItem.loudnessAlbumPeak,
            playCount: primaryItem.playCount,
            playPosition: primaryItem.playPosition,
            playProgress: primaryItem.playProgress,
            watched: primaryItem.watched,
            favorite: primaryItem.favorite,
            watchlist: primaryItem.watchlist,
            externalID: primaryItem.externalID,
            metadataProvider: primaryItem.metadataProvider,
            collectionTitle: primaryItem.collectionTitle,
            createdAt: primaryItem.createdAt,
            updatedAt: primaryItem.updatedAt,
            lastPlayedAt: primaryItem.lastPlayedAt,
            genre: primaryItem.genre
        )
    }
    
    /// 切换到下一条线路
    mutating func switchToNextRoute() -> Bool {
        let nextIndex = currentRouteIndex + 1
        guard nextIndex < routes.count else { return false }
        currentRouteIndex = nextIndex
        return true
    }
    
    /// 切换到指定线路
    mutating func switchToRoute(at index: Int) -> Bool {
        guard index >= 0 && index < routes.count else { return false }
        currentRouteIndex = index
        return true
    }
    
    /// 当前线路信息
    var currentRoute: PlayRoute? {
        guard currentRouteIndex < routes.count else { return nil }
        return routes[currentRouteIndex]
    }
}

/// 播放线路
public struct PlayRoute: Identifiable {
    public let id: String
    public let name: String
    public let url: String
    
    public init(id: String, name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}

// MARK: - Factory Extensions

extension MediaItemFactory {
    
    /// 从 IPTV 频道创建 PlayableMedia（支持多线路）
    static func makePlayableMedia(from channel: IPTVChannel) -> PlayableMedia? {
        guard !channel.urls.isEmpty else { return nil }
        
        // 创建所有线路
        let routes = channel.urls.enumerated().map { index, url in
            PlayRoute(
                id: "\(channel.sourceID)_\(channel.channelID)_\(index)",
                name: channel.urls.count > 1 ? "线路 \(index + 1)" : "默认线路",
                url: url
            )
        }
        
        // 创建主 MediaItem（使用第一条线路）
        guard let primaryItem = makeMediaItem(from: channel, urlIndex: 0) else {
            return nil
        }
        
        return PlayableMedia(
            primaryItem: primaryItem,
            routes: routes,
            currentRouteIndex: 0
        )
    }
    
    /// 从 VOD 视频创建 PlayableMedia（支持多线路）
    static func makePlayableMedia(from video: VODVideo, playLine: VODPlayLine) -> PlayableMedia? {
        guard !playLine.episodes.isEmpty else { return nil }
        
        // 创建所有剧集的线路
        let routes = playLine.episodes.map { episode in
            PlayRoute(
                id: "\(video.sourceID)_\(video.vodID)_\(playLine.name)_\(episode.name)",
                name: episode.name,
                url: episode.url
            )
        }
        
        // 创建主 MediaItem（使用第一集）
        let primaryItem = makeMediaItem(from: video, episode: playLine.episodes[0])
        
        return PlayableMedia(
            primaryItem: primaryItem,
            routes: routes,
            currentRouteIndex: 0
        )
    }
    
    /// 从 VOD 视频创建 PlayableMedia（指定剧集）
    static func makePlayableMedia(from video: VODVideo, episode: VODEpisode, allRoutes: [VODPlayLine]) -> PlayableMedia {
        // 从所有线路中找到包含该剧集的线路
        var routes: [PlayRoute] = []
        
        for playLine in allRoutes {
            if let matchedEpisode = playLine.episodes.first(where: { $0.name == episode.name }) {
                routes.append(PlayRoute(
                    id: "\(video.sourceID)_\(video.vodID)_\(playLine.name)_\(matchedEpisode.name)",
                    name: playLine.name,
                    url: matchedEpisode.url
                ))
            }
        }
        
        // 如果没有找到其他线路，至少包含当前剧集
        if routes.isEmpty {
            routes.append(PlayRoute(
                id: "\(video.sourceID)_\(video.vodID)_default_\(episode.name)",
                name: "默认线路",
                url: episode.url
            ))
        }
        
        let primaryItem = makeMediaItem(from: video, episode: episode)
        
        return PlayableMedia(
            primaryItem: primaryItem,
            routes: routes,
            currentRouteIndex: 0
        )
    }
}
