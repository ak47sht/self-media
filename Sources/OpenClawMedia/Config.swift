import Foundation
import Security

struct AppConfig: Codable, Equatable {
    var appName: String
    var movieBaseURL: URL
    var musicBaseURL: URL
    var iptvPlaylistURL: URL?
    var aiImageProviderBaseURL: URL?
    var aiImageProviderModel: String
    var aiImageAPIKey: String
    var apiTimeoutSeconds: Double
    var preferHTTPS: Bool
    var allowInsecureLocalhost: Bool

    enum CodingKeys: String, CodingKey {
        case appName
        case movieBaseURL
        case musicBaseURL
        case iptvPlaylistURL
        case aiImageProviderBaseURL
        case aiImageProviderModel
        case aiImageAPIKey
        case apiTimeoutSeconds
        case preferHTTPS
        case allowInsecureLocalhost
    }

    init(
        appName: String,
        movieBaseURL: URL,
        musicBaseURL: URL,
        iptvPlaylistURL: URL?,
        aiImageProviderBaseURL: URL?,
        aiImageProviderModel: String,
        aiImageAPIKey: String,
        apiTimeoutSeconds: Double,
        preferHTTPS: Bool,
        allowInsecureLocalhost: Bool
    ) {
        self.appName = appName
        self.movieBaseURL = movieBaseURL
        self.musicBaseURL = musicBaseURL
        self.iptvPlaylistURL = iptvPlaylistURL
        self.aiImageProviderBaseURL = aiImageProviderBaseURL
        self.aiImageProviderModel = aiImageProviderModel
        self.aiImageAPIKey = aiImageAPIKey
        self.apiTimeoutSeconds = apiTimeoutSeconds
        self.preferHTTPS = preferHTTPS
        self.allowInsecureLocalhost = allowInsecureLocalhost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? "OpenClaw Media"
        movieBaseURL = try container.decode(URL.self, forKey: .movieBaseURL)
        musicBaseURL = try container.decode(URL.self, forKey: .musicBaseURL)
        iptvPlaylistURL = try container.decodeIfPresent(URL.self, forKey: .iptvPlaylistURL)
        aiImageProviderBaseURL = try container.decodeIfPresent(URL.self, forKey: .aiImageProviderBaseURL)
        aiImageProviderModel = try container.decodeIfPresent(String.self, forKey: .aiImageProviderModel) ?? "provider-default"
        let storedAIImageAPIKey = AIProviderSecretStore.readAPIKey()
        let fileAIImageAPIKey = try container.decodeIfPresent(String.self, forKey: .aiImageAPIKey) ?? ""
        aiImageAPIKey = storedAIImageAPIKey ?? fileAIImageAPIKey
        apiTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .apiTimeoutSeconds) ?? 15
        preferHTTPS = try container.decodeIfPresent(Bool.self, forKey: .preferHTTPS) ?? true
        allowInsecureLocalhost = try container.decodeIfPresent(Bool.self, forKey: .allowInsecureLocalhost) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appName, forKey: .appName)
        try container.encode(movieBaseURL, forKey: .movieBaseURL)
        try container.encode(musicBaseURL, forKey: .musicBaseURL)
        try container.encodeIfPresent(iptvPlaylistURL, forKey: .iptvPlaylistURL)
        try container.encodeIfPresent(aiImageProviderBaseURL, forKey: .aiImageProviderBaseURL)
        try container.encode(aiImageProviderModel, forKey: .aiImageProviderModel)
        try container.encode(apiTimeoutSeconds, forKey: .apiTimeoutSeconds)
        try container.encode(preferHTTPS, forKey: .preferHTTPS)
        try container.encode(allowInsecureLocalhost, forKey: .allowInsecureLocalhost)
    }

    static let placeholder = AppConfig(
        appName: "OpenClaw Media",
        movieBaseURL: URL(string: "https://your-movie-domain.example/tools/movie-lite")!,
        musicBaseURL: URL(string: "https://your-music-domain.example/tools/music-lite")!,
        iptvPlaylistURL: nil,
        aiImageProviderBaseURL: URL(string: "https://api.example.com/v1"),
        aiImageProviderModel: "provider-default",
        aiImageAPIKey: "",
        apiTimeoutSeconds: 15,
        preferHTTPS: true,
        allowInsecureLocalhost: false
    )

    var needsSetup: Bool {
        movieBaseURL.host?.contains("example") == true || musicBaseURL.host?.contains("example") == true
    }

    var reloadIdentity: String {
        [
            movieBaseURL.absoluteString,
            musicBaseURL.absoluteString,
            iptvPlaylistURL?.absoluteString ?? "",
            aiImageProviderBaseURL?.absoluteString ?? "",
            aiImageProviderModel,
            String(apiTimeoutSeconds),
            String(preferHTTPS),
            String(allowInsecureLocalhost)
        ].joined(separator: "|")
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
        var urls: [URL] = [ConfigStore.applicationSupportConfigURL(fileManager: fileManager)]
        urls.append(URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("config.local.json"))
        urls.append(URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("config.example.json"))
        return urls
    }
}

enum AIProviderSecretStore {
    private static let service = "com.openclaw.media.ai-image-provider"
    private static let account = "default"

    static func readAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    static func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteAPIKey()
            return
        }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound { throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus)) }
        var add = query
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus)) }
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum ConfigStore {
    static func applicationSupportConfigURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
        return base.appendingPathComponent("OpenClawMedia/config.json")
    }

    static func save(_ config: AppConfig, fileManager: FileManager = .default) throws {
        try AIProviderSecretStore.saveAPIKey(config.aiImageAPIKey)
        let url = applicationSupportConfigURL(fileManager: fileManager)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config)
        try data.write(to: url, options: [.atomic])
    }
}
