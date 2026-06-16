import Foundation

/// VOD 视频点播模型
/// 对应 CMS API (苹果CMS/飞飞CMS) 的 vod 数据结构
public struct VODVideo: Identifiable, Codable, Sendable, Equatable {
    public let id: String          // vod_id (sourceID_vodID)
    public let sourceID: String    // 来源 MediaSource 的 ID
    public let vodID: String       // 源站 vod_id
    public let name: String        // vod_name
    public let type: String?       // type_name (电影/剧集/动漫/综艺)
    public let year: String?       // vod_year
    public let area: String?       // vod_area
    public let lang: String?       // vod_lang
    public let pic: String?        // vod_pic (封面图)
    public let actors: String?     // vod_actor
    public let director: String?   // vod_director
    public let content: String?    // vod_content (简介)
    public let playURLs: [VODPlayLine]  // 播放线路列表
    public let updatedAt: Date?    // 更新时间
    
    public init(
        sourceID: String,
        vodID: String,
        name: String,
        type: String? = nil,
        year: String? = nil,
        area: String? = nil,
        lang: String? = nil,
        pic: String? = nil,
        actors: String? = nil,
        director: String? = nil,
        content: String? = nil,
        playURLs: [VODPlayLine] = [],
        updatedAt: Date? = nil
    ) {
        self.id = "\(sourceID)_\(vodID)"
        self.sourceID = sourceID
        self.vodID = vodID
        self.name = name
        self.type = type
        self.year = year
        self.area = area
        self.lang = lang
        self.pic = pic
        self.actors = actors
        self.director = director
        self.content = content
        self.playURLs = playURLs
        self.updatedAt = updatedAt
    }
    
    /// 从 CMS JSON API 解析
    /// 格式: vod_play_url = "线路1$第1集$url1#第2集$url2$$线路2$第1集$url3"
    public static func parseFromCMS(json: [String: Any], sourceID: String) -> VODVideo? {
        guard let vodID = json["vod_id"] as? Int,
              let name = json["vod_name"] as? String else {
            return nil
        }
        
        let type = json["type_name"] as? String
        let year = json["vod_year"] as? String
        let area = json["vod_area"] as? String
        let lang = json["vod_lang"] as? String
        let pic = json["vod_pic"] as? String
        let actors = json["vod_actor"] as? String
        let director = json["vod_director"] as? String
        let content = json["vod_content"] as? String
        
        // 解析播放地址
        let playURLs: [VODPlayLine]
        if let playURLStr = json["vod_play_url"] as? String {
            playURLs = VODPlayLine.parse(from: playURLStr)
        } else {
            playURLs = []
        }
        
        return VODVideo(
            sourceID: sourceID,
            vodID: String(vodID),
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
            updatedAt: Date()
        )
    }
}

/// VOD 播放线路
/// 一个视频可能有多个播放源（线路1、线路2）
public struct VODPlayLine: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String        // 线路名称（如 "线路1", "HD", "蓝光"）
    public let episodes: [VODEpisode]  // 剧集列表
    
    public init(name: String, episodes: [VODEpisode]) {
        self.id = UUID().uuidString
        self.name = name
        self.episodes = episodes
    }
    
    // 手动实现 Equatable，基于 name 和 episodes 比较（忽略 id）
    public static func == (lhs: VODPlayLine, rhs: VODPlayLine) -> Bool {
        lhs.name == rhs.name && lhs.episodes == rhs.episodes
    }
    
    /// 从 CMS 播放地址字符串解析
    /// 格式: "线路1$第1集$url1#第2集$url2$$线路2$第1集$url3#第2集$url4"
    /// 分隔符: $$ 分隔线路, # 分隔剧集, $ 分隔名称和URL
    public static func parse(from playURL: String) -> [VODPlayLine] {
        var lines: [VODPlayLine] = []
        
        // 按 $$ 分割线路
        let lineStrings = playURL.components(separatedBy: "$$")
        
        for (index, lineStr) in lineStrings.enumerated() {
            guard !lineStr.isEmpty else { continue }
            
            // 按 # 分割剧集
            let episodeStrings = lineStr.components(separatedBy: "#")
            var episodes: [VODEpisode] = []
            
            for episodeStr in episodeStrings {
                guard !episodeStr.isEmpty else { continue }
                
                // 按 $ 分割名称和URL
                let parts = episodeStr.components(separatedBy: "$")
                if parts.count >= 2 {
                    let name = parts[0].trimmingCharacters(in: .whitespaces)
                    let url = parts[1].trimmingCharacters(in: .whitespaces)
                    episodes.append(VODEpisode(name: name, url: url))
                }
            }
            
            if !episodes.isEmpty {
                let lineName = episodes.first?.name.contains("线路") == true
                    ? episodes.first!.name
                    : "线路\(index + 1)"
                lines.append(VODPlayLine(name: lineName, episodes: episodes))
            }
        }
        
        return lines
    }
}

/// VOD 剧集
public struct VODEpisode: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String    // 剧集名称（如 "第1集", "EP01"）
    public let url: String     // 播放地址
    
    public init(name: String, url: String) {
        self.id = UUID().uuidString
        self.name = name
        self.url = url
    }
    
    // 手动实现 Equatable，基于 name 和 url 比较（忽略 id）
    public static func == (lhs: VODEpisode, rhs: VODEpisode) -> Bool {
        lhs.name == rhs.name && lhs.url == rhs.url
    }
}

/// VOD 分类
public struct VODCategory: Identifiable, Codable, Sendable, Equatable {
    public let id: Int           // type_id
    public let parentID: Int     // type_pid
    public let name: String      // type_name
    
    public init(id: Int, parentID: Int, name: String) {
        self.id = id
        self.parentID = parentID
        self.name = name
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "type_id"
        case parentID = "type_pid"
        case name = "type_name"
    }
}
