import Foundation

/// 敏感凭据（第三方 API Key / Shared Secret / OAuth Token）的本地存储。
///
/// 将 secret 单独存放到 Application Support 下的 `0600` 文件，避免继续扩散到全局偏好设置。
/// 本存储不做加密，仅靠文件权限收敛暴露面；如需更强保护，可在此叠加加密或 Keychain。
public final class SecretStore {
    private let fileURL: URL?

    /// - Parameter directory: 存储目录。默认 `Application Support/MediaLib/Credentials`；测试可注入临时目录以隔离。
    public init(directory: URL? = nil) {
        let baseDirectory = directory ?? Self.defaultDirectory()
        if let baseDirectory {
            try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
            self.fileURL = baseDirectory.appendingPathComponent("AppSecrets.json")
        } else {
            self.fileURL = nil
        }
    }

    /// 读取全部 secret 键值；文件不存在或解析失败返回空字典。
    public func load() -> [String: String] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    /// 覆盖写入全部 secret 键值。空字典会清空文件内容（仍写入 `{}`，保持文件存在与权限）。
    public func save(_ secrets: [String: String]) {
        guard let fileURL,
              let data = try? JSONEncoder().encode(secrets) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func defaultDirectory() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return base
            .appendingPathComponent("MediaLib", isDirectory: true)
            .appendingPathComponent("Credentials", isDirectory: true)
    }
}
