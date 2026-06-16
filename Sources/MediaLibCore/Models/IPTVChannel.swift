import Foundation

/// IPTV 直播频道
public struct IPTVChannel: Identifiable, Codable, Equatable, Hashable {
    public let sourceID: String      // 来源 MediaSource 的 ID
    public let channelID: String     // 频道 ID（对应数据库 channel_id）
    public let name: String          // 频道名称
    public let urls: [String]        // 播放地址列表（支持多线路）
    public let groupTitle: String?   // 分组名称（如"央视频道"、"卫视频道"）
    public let logo: String?         // 台标 URL
    public let updatedAt: Date?      // 缓存更新时间
    
    /// Identifiable.id: sourceID + channelID 组合
    public var id: String {
        "\(sourceID)_\(channelID)"
    }
    
    /// 主播放地址（使用第一个 URL）
    public var primaryURL: String {
        urls.first ?? ""
    }
    
    public init(
        sourceID: String,
        channelID: String,
        name: String,
        urls: [String],
        groupTitle: String? = nil,
        logo: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.sourceID = sourceID
        self.channelID = channelID
        self.name = name
        self.urls = urls
        self.groupTitle = groupTitle
        self.logo = logo
        self.updatedAt = updatedAt
    }
    
    /// 从 M3U 标签行解析频道信息
    /// 格式: #EXTINF:-1 tvg-id="cctv1" tvg-name="CCTV1" tvg-logo="..." group-title="央视",CCTV1综合
    public static func parse(from extinf: String, url: String, sourceID: String) -> IPTVChannel? {
        // 提取频道名称（逗号后面的部分）
        let components = extinf.components(separatedBy: ",")
        guard components.count >= 2 else { return nil }
        let name = components.dropFirst().joined(separator: ",").trimmingCharacters(in: .whitespaces)
        
        // 提取属性
        var groupTitle: String?
        var logo: String?
        var tvgID: String?
        
        let attributesString = components[0]
        
        // 解析 group-title
        if let groupRange = attributesString.range(of: #"group-title="([^"]*)"#, options: .regularExpression) {
            let match = attributesString[groupRange]
            if let valueRange = match.range(of: #""([^"]*)"#, options: .regularExpression) {
                groupTitle = String(match[valueRange]).replacingOccurrences(of: "\"", with: "")
            }
        }
        
        // 解析 tvg-logo
        if let logoRange = attributesString.range(of: #"tvg-logo="([^"]*)"#, options: .regularExpression) {
            let match = attributesString[logoRange]
            if let valueRange = match.range(of: #""([^"]*)"#, options: .regularExpression) {
                logo = String(match[valueRange]).replacingOccurrences(of: "\"", with: "")
            }
        }
        
        // 解析 tvg-id
        if let idRange = attributesString.range(of: #"tvg-id="([^"]*)"#, options: .regularExpression) {
            let match = attributesString[idRange]
            if let valueRange = match.range(of: #""([^"]*)"#, options: .regularExpression) {
                tvgID = String(match[valueRange]).replacingOccurrences(of: "\"", with: "")
            }
        }
        
        // 生成 channel ID（使用 tvg-id 或 name hash）
        let channelID: String
        if let tvgID = tvgID, !tvgID.isEmpty {
            channelID = tvgID
        } else {
            // 使用 name + url hash 作为 ID
            channelID = "\(name)_\(url.hashValue)".replacingOccurrences(of: " ", with: "_")
        }
        
        return IPTVChannel(
            sourceID: sourceID,
            channelID: channelID,
            name: name,
            urls: [url],  // M3U 每行只有一个 URL，多线路需要后期聚合
            groupTitle: groupTitle,
            logo: logo,
            updatedAt: Date()
        )
    }
}
