import Foundation

struct AppConfig: Codable, Equatable {
    var appName: String
    var movieBaseURL: URL
    var musicBaseURL: URL
    var apiTimeoutSeconds: Double
    var preferHTTPS: Bool
    var allowInsecureLocalhost: Bool

    static let placeholder = AppConfig(
        appName: "OpenClaw Media",
        movieBaseURL: URL(string: "https://your-movie-domain.example")!,
        musicBaseURL: URL(string: "https://your-music-domain.example")!,
        apiTimeoutSeconds: 15,
        preferHTTPS: true,
        allowInsecureLocalhost: false
    )

    var needsSetup: Bool {
        movieBaseURL.host?.contains("example") == true || musicBaseURL.host?.contains("example") == true
    }
}

enum ConfigLoader {
    static func load(fileManager: FileManager = .default) -> AppConfig {
        let decoder = JSONDecoder()
        for url in candidateURLs(fileManager: fileManager) {
            guard let data = try? Data(contentsOf: url),
                  let config = try? decoder.decode(AppConfig.self, from: data) else { continue }
            return config
        }
        return .placeholder
    }

    static func candidateURLs(fileManager: FileManager = .default) -> [URL] {
        var urls: [URL] = [URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("config.local.json")]
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(appSupport.appendingPathComponent("OpenClawMedia/config.json"))
        }
        urls.append(URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("config.example.json"))
        return urls
    }
}
