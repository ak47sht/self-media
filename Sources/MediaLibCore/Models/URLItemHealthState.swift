import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URL 媒体链接的健康状态：通过可达性与是否可解析判断。
public enum URLItemHealthState: String, Sendable {
    case unknown
    case checking
    case ok
    case unreachable
    case unparseable

    public var isUnhealthy: Bool { self == .unreachable || self == .unparseable }

    public var displayName: String {
        switch self {
        case .unknown: return "未检查"
        case .checking: return "检查中"
        case .ok: return "可访问"
        case .unreachable: return "无法访问"
        case .unparseable: return "无法解析"
        }
    }
}

public enum URLSourceHealthClassifier {
    public static func classify(_ response: URLResponse) -> URLItemHealthState {
        guard let http = response as? HTTPURLResponse else { return .ok }
        if http.statusCode >= 400 { return .unreachable }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("text/html") || contentType.contains("application/xhtml") {
            return .unparseable
        }
        return .ok
    }
}
