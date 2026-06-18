import Foundation
import MediaLibCore

struct OnlineSourcePreview: Sendable {
    let title: String
    let message: String
    let samples: [String]
}

actor OnlineSourcePreviewService {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: configuration)
    }

    func previewVOD(apiBase: String) async throws -> OnlineSourcePreview {
        let listJSON = try await requestCMSJSON(apiBase: apiBase, queryItems: [
            URLQueryItem(name: "ac", value: "list"),
            URLQueryItem(name: "pg", value: "1")
        ])
        let categories = (listJSON["class"] as? [[String: Any]]) ?? []
        let listCount = (listJSON["list"] as? [[String: Any]])?.count ?? 0
        let total = intValue(listJSON["total"]) ?? listCount
        let categoryNames = categories.compactMap { $0["type_name"] as? String }.prefix(8)

        if !categories.isEmpty {
            return OnlineSourcePreview(
                title: "VOD 源可用",
                message: "分类 \(categories.count) 个，首页条目 \(listCount) 个，总量约 \(total) 个。",
                samples: Array(categoryNames)
            )
        }

        let detailJSON = try await requestCMSJSON(apiBase: apiBase, queryItems: [
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "pg", value: "1")
        ])
        let videos = (detailJSON["list"] as? [[String: Any]]) ?? []
        let names = videos.compactMap { $0["vod_name"] as? String }.prefix(8)
        return OnlineSourcePreview(
            title: videos.isEmpty ? "VOD 源已响应" : "VOD 源可用",
            message: "未返回分类，首页视频 \(videos.count) 个。",
            samples: Array(names)
        )
    }

    private func requestCMSJSON(apiBase: String, queryItems: [URLQueryItem]) async throws -> [String: Any] {
        guard var components = URLComponents(string: apiBase.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw OnlineSourcePreviewError.invalidURL
        }
        let existing = components.queryItems ?? []
        components.queryItems = existing + queryItems
        guard let url = components.url else { throw OnlineSourcePreviewError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("MediaLIB/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OnlineSourcePreviewError.httpStatus(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OnlineSourcePreviewError.invalidJSON
        }
        return json
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

enum OnlineSourcePreviewError: LocalizedError {
    case invalidURL
    case invalidJSON
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "源地址无效。"
        case .invalidJSON:
            return "源返回的不是可识别 JSON。"
        case .httpStatus(let status):
            return "源请求失败（HTTP \(status)）。"
        }
    }
}
