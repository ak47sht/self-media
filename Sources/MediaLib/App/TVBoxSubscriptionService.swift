import Foundation
import MediaLibCore

struct TVBoxSubscriptionPreview: Sendable {
    let subscriptionURL: String
    let vodSites: [TVBoxVODSite]
    let liveSources: [TVBoxLiveSource]
    let unsupportedSiteCount: Int
    let spiderURL: String?

    var supportedCount: Int { vodSites.count + liveSources.count }
}

struct TVBoxVODSite: Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let api: String
    let searchable: Bool
    let filterable: Bool

    var id: String { key.isEmpty ? api : key }
}

struct TVBoxLiveSource: Identifiable, Hashable, Sendable {
    let name: String
    let url: String

    var id: String { "\(name)-\(url)" }
}

actor TVBoxSubscriptionService {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)
    }

    func fetchPreview(from subscriptionURL: String) async throws -> TVBoxSubscriptionPreview {
        let trimmed = subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { throw TVBoxSubscriptionError.invalidURL }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw TVBoxSubscriptionError.unsupportedScheme
        }
        var request = URLRequest(url: url)
        request.setValue("MediaLIB/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TVBoxSubscriptionError.httpStatus(http.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TVBoxSubscriptionError.invalidJSON
        }

        let sites = (root["sites"] as? [[String: Any]]) ?? []
        let vodSites = sites.compactMap(Self.parseSupportedVODSite)
        let unsupportedCount = sites.count - vodSites.count
        let lives = ((root["lives"] as? [[String: Any]]) ?? []).compactMap(Self.parseLiveSource)
        let spider = root["spider"] as? String
        return TVBoxSubscriptionPreview(
            subscriptionURL: trimmed,
            vodSites: vodSites,
            liveSources: lives,
            unsupportedSiteCount: max(unsupportedCount, 0),
            spiderURL: spider?.isEmpty == false ? spider : nil
        )
    }

    private static func parseSupportedVODSite(_ site: [String: Any]) -> TVBoxVODSite? {
        let type = site["type"] as? Int ?? Int(site["type"] as? String ?? "") ?? -1
        guard type == 1,
              let api = site["api"] as? String,
              !api.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let key = (site["key"] as? String) ?? api
        let name = ((site["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? key
        return TVBoxVODSite(
            key: key,
            name: name,
            api: api,
            searchable: Self.boolValue(site["searchable"]),
            filterable: Self.boolValue(site["filterable"])
        )
    }

    private static func parseLiveSource(_ live: [String: Any]) -> TVBoxLiveSource? {
        guard let url = live["url"] as? String,
              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let name = ((live["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "TVBox 直播"
        return TVBoxLiveSource(name: name, url: url)
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let string = value as? String { return string == "1" || string.lowercased() == "true" }
        return false
    }
}

enum TVBoxSubscriptionError: LocalizedError {
    case invalidURL
    case unsupportedScheme
    case invalidJSON
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "TVBox 订阅地址无效。"
        case .unsupportedScheme:
            return "TVBox 订阅地址仅支持 http/https 协议。"
        case .invalidJSON:
            return "TVBox 订阅返回的不是可识别 JSON。"
        case .httpStatus(let status):
            return "TVBox 订阅请求失败（HTTP \(status)）。"
        }
    }
}
