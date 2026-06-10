import Foundation

struct AppUpdateRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }

    let tagName: String
    let name: String?
    let htmlURL: URL
    let assets: [Asset]
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
        case publishedAt = "published_at"
    }

    var dmgAsset: Asset? {
        assets.first { asset in
            asset.name.lowercased().hasSuffix(".dmg")
        }
    }
}

enum AppUpdateChecker {
    static let releaseTag = "latest"
    static let releaseURL = URL(string: "https://api.github.com/repos/ak47sht/self-media/releases/tags/latest")!

    static func check() async throws -> AppUpdateRelease {
        var request = URLRequest(url: releaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OpenClawMedia", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(AppUpdateRelease.self, from: data)
    }

    static var currentVersionSummary: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "local"
        return "v\(version) (build \(build))"
    }
}
