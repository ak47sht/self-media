import XCTest
import Foundation
@testable import MediaLibCore

final class MediaDetailRepositoryTests: XCTestCase {
    private var tempDir: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaDetailRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        databaseURL = tempDir.appendingPathComponent("MediaLib.sqlite")
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testSchemaCreatesDetailTablesAtCurrentVersion() throws {
        let database = try DatabaseManager(url: databaseURL)
        XCTAssertEqual(try database.schemaVersion(), DatabaseManager.currentSchemaVersion)

        let tables = try tableNames(database)
        XCTAssertTrue(tables.contains("media_detail_metadata"))
        XCTAssertTrue(tables.contains("media_external_ids"))
        XCTAssertTrue(tables.contains("media_people"))
        XCTAssertTrue(tables.contains("media_person_external_ids"))
        XCTAssertTrue(tables.contains("media_credits"))
        XCTAssertTrue(tables.contains("media_artwork"))
        XCTAssertTrue(tables.contains("media_related_titles"))
        XCTAssertTrue(tables.contains("media_detail_backfill_jobs"))
    }

    func testSaveAndFetchDetailSnapshotRoundTrips() throws {
        let database = try DatabaseManager(url: databaseURL)
        let mediaRepository = MediaRepository(database: database)
        let detailRepository = MediaDetailRepository(database: database)
        let item = MediaItem(id: "movie-1", type: .movie, title: "Example Movie")
        try mediaRepository.upsert(item)

        let snapshot = MediaDetailSnapshot(
            metadata: MediaDetailMetadata(
                mediaID: item.id,
                status: "Released",
                firstAirDate: "2025-01-01",
                endDate: nil,
                seasonCount: nil,
                episodeCount: nil,
                contentRating: "PG-13",
                originalLanguage: "en",
                countries: ["US"],
                productionCompanies: ["Example Studio"],
                networks: [],
                trailerURL: "https://example.com/trailer",
                provider: "tmdb",
                language: "zh-CN",
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                fetchVersion: 1
            ),
            externalIDs: [MediaExternalID(provider: "tmdb", value: "123")],
            people: [MediaPerson(id: "person-1", name: "Actor One")],
            credits: [
                MediaCredit(
                    id: "credit-1",
                    mediaID: item.id,
                    personID: "person-1",
                    category: "cast",
                    role: "Hero",
                    department: "Acting",
                    order: 1
                )
            ],
            artwork: [
                MediaArtwork(
                    id: "art-1",
                    mediaID: item.id,
                    kind: "backdrop",
                    thumbURL: "https://example.com/thumb.jpg",
                    fullURL: "https://example.com/full.jpg",
                    language: nil,
                    aspectRatio: 1.78,
                    order: 0,
                    localPath: nil
                )
            ],
            relatedTitles: [
                MediaRelatedTitle(
                    id: "related-1",
                    mediaID: item.id,
                    relation: "similar",
                    externalID: "tmdb:456",
                    title: "Related Movie",
                    year: 2024,
                    posterURL: nil,
                    overview: nil,
                    rating: 7.2,
                    popularity: 10,
                    localMediaID: nil,
                    order: 0
                )
            ]
        )
        try detailRepository.save(snapshot)

        let fetched = try XCTUnwrap(detailRepository.fetch(mediaID: item.id))
        let fetchedPerson = try XCTUnwrap(detailRepository.fetchPerson(id: "person-1"))
        XCTAssertEqual(fetchedPerson.name, "Actor One")
        XCTAssertEqual(fetched.metadata.mediaID, item.id)
        XCTAssertEqual(fetched.metadata.status, "Released")
        XCTAssertEqual(fetched.externalIDs, snapshot.externalIDs)
        XCTAssertEqual(fetched.credits.map(\.personID), ["person-1"])
        XCTAssertEqual(fetched.artwork.map(\.fullURL), ["https://example.com/full.jpg"])
        XCTAssertEqual(fetched.relatedTitles.map(\.title), ["Related Movie"])
    }

    func testDeletingMediaItemCascadesDetailRows() throws {
        let database = try DatabaseManager(url: databaseURL)
        let mediaRepository = MediaRepository(database: database)
        let detailRepository = MediaDetailRepository(database: database)
        let item = MediaItem(id: "movie-cascade", type: .movie, title: "Cascade")
        try mediaRepository.upsert(item)
        try detailRepository.save(MediaDetailSnapshot(metadata: MediaDetailMetadata(mediaID: item.id, provider: "tmdb", language: "zh-CN")))
        try detailRepository.prepareBackfill(mediaIDs: [item.id])

        try mediaRepository.deleteItems(ids: [item.id])

        XCTAssertNil(try detailRepository.fetch(mediaID: item.id))
        let pending = try detailRepository.pendingBackfillMediaIDs(limit: 10)
        XCTAssertFalse(pending.contains(item.id))
    }

    private func tableNames(_ database: DatabaseManager) throws -> Set<String> {
        let names = try database.query("SELECT name FROM sqlite_master WHERE type = 'table'") { row in
            row.string(0) ?? ""
        }
        return Set(names.filter { !$0.isEmpty })
    }
}
