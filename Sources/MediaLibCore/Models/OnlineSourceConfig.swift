import Foundation

/// Configuration for online sources (IPTV, VOD, OnlineMusic)
public struct OnlineSourceConfig: Codable, Hashable, Sendable {
    public var kind: OnlineSourceKind
    public var provider: String?
    public var apiBase: String?
    public var subscriptionURL: String?
    public var epgURL: String?
    public var userAgent: String?
    public var quality: String?
    public var needsParser: Bool
    
    public init(
        kind: OnlineSourceKind,
        provider: String? = nil,
        apiBase: String? = nil,
        subscriptionURL: String? = nil,
        epgURL: String? = nil,
        userAgent: String? = nil,
        quality: String? = nil,
        needsParser: Bool = false
    ) {
        self.kind = kind
        self.provider = provider
        self.apiBase = apiBase
        self.subscriptionURL = subscriptionURL
        self.epgURL = epgURL
        self.userAgent = userAgent
        self.quality = quality
        self.needsParser = needsParser
    }
}

public enum OnlineSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case iptv
    case vodJSONAPI = "vod_json_api"
    case vodTVBox = "vod_tvbox"
    case vodTVBoxAggregate = "vod_tvbox_aggregate"
    case onlineMusicNetease = "online_music_netease"
    case onlineMusicGDStudio = "online_music_gdstudio"
    case onlineMusicTabos = "online_music_tabos"
    case onlineMusicCustom = "online_music_custom"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .iptv: return "IPTV 直播"
        case .vodJSONAPI: return "点播源 (JSON API)"
        case .vodTVBox: return "点播源 (TVBox)"
        case .vodTVBoxAggregate: return "TVBox 聚合源"
        case .onlineMusicNetease: return "网易云音乐"
        case .onlineMusicGDStudio: return "GD Studio 音乐"
        case .onlineMusicTabos: return "Tabos 聚合音乐"
        case .onlineMusicCustom: return "自定义音乐源"
        }
    }
}
