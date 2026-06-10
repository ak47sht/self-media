import Foundation
import Security

struct AppConfig: Codable, Equatable {
    var appName: String
    var movieBaseURL: URL
    var musicBaseURL: URL
    var iptvPlaylistURL: URL?
    var vodConfigURL: URL?
    var jsSourceImportURL: URL?
    var musicUnlockCodeHash: String
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
        case vodConfigURL
        case jsSourceImportURL
        case musicUnlockCodeHash
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
        vodConfigURL: URL? = nil,
        jsSourceImportURL: URL? = nil,
        musicUnlockCodeHash: String = "",
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
        self.vodConfigURL = vodConfigURL
        self.jsSourceImportURL = jsSourceImportURL
        self.musicUnlockCodeHash = musicUnlockCodeHash
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
        vodConfigURL = try container.decodeIfPresent(URL.self, forKey: .vodConfigURL)
        jsSourceImportURL = try container.decodeIfPresent(URL.self, forKey: .jsSourceImportURL)
        musicUnlockCodeHash = try container.decodeIfPresent(String.self, forKey: .musicUnlockCodeHash) ?? ""
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
        try container.encodeIfPresent(vodConfigURL, forKey: .vodConfigURL)
        try container.encodeIfPresent(jsSourceImportURL, forKey: .jsSourceImportURL)
        try container.encode(musicUnlockCodeHash, forKey: .musicUnlockCodeHash)
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
        vodConfigURL: nil,
        jsSourceImportURL: nil,
        musicUnlockCodeHash: "",
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
            vodConfigURL?.absoluteString ?? "",
            jsSourceImportURL?.absoluteString ?? "",
            musicUnlockCodeHash,
            aiImageProviderBaseURL?.absoluteString ?? "",
            aiImageProviderModel,
            String(apiTimeoutSeconds),
            String(preferHTTPS),
            String(allowInsecureLocalhost)
        ].joined(separator: "|")
    }

    var isMusicUnlocked: Bool {
        let value = musicUnlockCodeHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        return value == SourcePresets.musicUnlockCodeHash
    }

    static func sha256Hex(_ text: String) -> String {
        // Pure Swift SHA-256 keeps the package buildable in lightweight CI
        // environments without additional crypto framework imports.
        let bytes = Array(Data(text.utf8))
        let bitLength = UInt64(bytes.count * 8)
        var message = bytes + [0x80]
        while message.count % 64 != 56 { message.append(0) }
        message += stride(from: 56, through: 0, by: -8).map { UInt8((bitLength >> UInt64($0)) & 0xff) }

        var h0: UInt32 = 0x6a09e667
        var h1: UInt32 = 0xbb67ae85
        var h2: UInt32 = 0x3c6ef372
        var h3: UInt32 = 0xa54ff53a
        var h4: UInt32 = 0x510e527f
        var h5: UInt32 = 0x9b05688c
        var h6: UInt32 = 0x1f83d9ab
        var h7: UInt32 = 0x5be0cd19

        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        ]

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            let chunk = Array(message[chunkStart..<chunkStart + 64])
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let j = i * 4
                w[i] = (UInt32(chunk[j]) << 24) | (UInt32(chunk[j + 1]) << 16) | (UInt32(chunk[j + 2]) << 8) | UInt32(chunk[j + 3])
            }
            for i in 16..<64 {
                let s0 = w[i - 15].rightRotated(by: 7) ^ w[i - 15].rightRotated(by: 18) ^ (w[i - 15] >> 3)
                let s1 = w[i - 2].rightRotated(by: 17) ^ w[i - 2].rightRotated(by: 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7
            for i in 0..<64 {
                let s1 = e.rightRotated(by: 6) ^ e.rightRotated(by: 11) ^ e.rightRotated(by: 25)
                let ch = (e & f) ^ ((~e) & g)
                let temp1 = h &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = a.rightRotated(by: 2) ^ a.rightRotated(by: 13) ^ a.rightRotated(by: 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                h = g; g = f; f = e; e = d &+ temp1; d = c; c = b; b = a; a = temp1 &+ temp2
            }
            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d
            h4 = h4 &+ e; h5 = h5 &+ f; h6 = h6 &+ g; h7 = h7 &+ h
        }
        return [h0, h1, h2, h3, h4, h5, h6, h7].map { String(format: "%08x", $0) }.joined()
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

private extension UInt32 {
    func rightRotated(by amount: UInt32) -> UInt32 {
        (self >> amount) | (self << (32 - amount))
    }
}
