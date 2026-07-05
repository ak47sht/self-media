import XCTest
import Foundation
@testable import MediaLibCore

final class SecretStoreAuditTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecretStoreAudit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testSecretStoreFilePermissionsAreStrictly600() throws {
        let store = SecretStore(directory: tempDir)
        let secrets = ["tmdb_api_key": "secret-token-12345", "trakt_client_id": "oauth-client-id-999"]

        store.save(secrets)

        let fileURL = tempDir.appendingPathComponent("AppSecrets.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = attributes[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)

        let reloaded = store.load()
        XCTAssertEqual(reloaded["tmdb_api_key"], "secret-token-12345")
        XCTAssertEqual(reloaded["trakt_client_id"], "oauth-client-id-999")
    }

    func testSecretStoreSurvivesCorruptedOrMalformedJSONFile() throws {
        let store = SecretStore(directory: tempDir)
        let fileURL = tempDir.appendingPathComponent("AppSecrets.json")

        let corruptedData = Data("{\"tmdb_api_key\": \"broken-json...".utf8)
        try corruptedData.write(to: fileURL)

        let loaded = store.load()
        XCTAssertTrue(loaded.isEmpty)
    }
}
