import Foundation
import MediaLibCore

/// M3U/M3U8 播放列表解析器
public struct M3UParser {
    
    /// 解析 M3U 文本内容
    /// - Parameters:
    ///   - content: M3U 文本内容
    ///   - sourceID: 来源 MediaSource 的 ID
    /// - Returns: 解析出的频道列表
    public static func parse(_ content: String, sourceID: String) -> [IPTVChannel] {
        var channels: [IPTVChannel] = []
        
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // 检查是否是 M3U 格式
        guard let firstLine = lines.first, firstLine.hasPrefix("#EXTM3U") else {
            return []
        }
        
        var currentEXTINF: String?
        
        for line in lines.dropFirst() {
            if line.hasPrefix("#EXTINF:") {
                // 记录当前的 EXTINF 行
                currentEXTINF = line
            } else if !line.hasPrefix("#") {
                // 这是 URL 行
                if let extinf = currentEXTINF {
                    if let channel = IPTVChannel.parse(from: extinf, url: line, sourceID: sourceID) {
                        channels.append(channel)
                    }
                }
                currentEXTINF = nil
            }
            // 其他 # 开头的行（如 #EXT-X-VERSION）忽略
        }
        
        return channels
    }
    
    /// 从 URL 拉取并解析 M3U
    /// - Parameters:
    ///   - url: M3U 订阅地址
    ///   - sourceID: 来源 MediaSource 的 ID
    /// - Returns: 解析出的频道列表
    public static func fetch(from url: String, sourceID: String) async throws -> [IPTVChannel] {
        guard let requestURL = URL(string: url) else {
            throw M3UParserError.invalidURL
        }
        
        var request = URLRequest(url: requestURL)
        request.setValue("MediaLib/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await HTTPClient.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw M3UParserError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        guard let content = String(data: data, encoding: .utf8) else {
            throw M3UParserError.decodingFailed
        }
        
        return parse(content, sourceID: sourceID)
    }
}

/// M3U 解析错误
public enum M3UParserError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case decodingFailed
    case invalidFormat
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 M3U 订阅地址"
        case .httpError(let code):
            return "HTTP 请求失败: \(code)"
        case .decodingFailed:
            return "无法解码 M3U 内容（非 UTF-8 编码）"
        case .invalidFormat:
            return "不是有效的 M3U 格式"
        }
    }
}
