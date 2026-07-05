import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MediaLibCore

private final class MockURLProtocol: URLProtocol {
    struct Stub { let status: Int; let headers: [String: String]; let body: Data }

    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var _stubs: [Stub] = []
    nonisolated(unsafe) private static var _requestCount = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _requestCount
    }

    static func setStubs(_ stubs: [Stub]) {
        lock.lock()
        defer { lock.unlock() }
        _stubs = stubs
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _stubs = []
        _requestCount = 0
    }

    private static func nextStub() -> Stub {
        lock.lock()
        defer { lock.unlock() }
        let index = min(_requestCount, _stubs.count - 1)
        _requestCount += 1
        return _stubs[max(index, 0)]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub = MockURLProtocol.nextStub()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: nil,
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class HTTPClientTests: XCTestCase {
    private func makeClient(maxRetries: Int = 2) -> HTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return HTTPClient(session: session, maxRetries: maxRetries, retryDelay: { _, _ in 0 })
    }

    private func getRequest() -> URLRequest {
        URLRequest(url: URL(string: "https://example.com/items")!)
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    func testRetriesOn429ThenSucceeds() async throws {
        MockURLProtocol.setStubs([
            .init(status: 429, headers: ["Retry-After": "0"], body: Data()),
            .init(status: 200, headers: [:], body: Data("ok".utf8))
        ])
        let (data, response) = try await makeClient().data(for: getRequest())
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testRetriesOn500UpToMaxThenReturnsLast() async throws {
        MockURLProtocol.setStubs([.init(status: 500, headers: [:], body: Data())])
        let (_, response) = try await makeClient(maxRetries: 2).data(for: getRequest())
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 500)
        XCTAssertEqual(MockURLProtocol.requestCount, 3)
    }

    func testDoesNotRetryNonIdempotentPOST() async throws {
        MockURLProtocol.setStubs([
            .init(status: 500, headers: [:], body: Data()),
            .init(status: 200, headers: [:], body: Data())
        ])
        var request = getRequest()
        request.httpMethod = "POST"
        let (_, response) = try await makeClient().data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 500)
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testSuccessIssuesSingleRequest() async throws {
        MockURLProtocol.setStubs([.init(status: 200, headers: [:], body: Data("hi".utf8))])
        let (data, _) = try await makeClient().data(for: getRequest())
        XCTAssertEqual(String(data: data, encoding: .utf8), "hi")
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testDefaultRetryDelayPrefersRetryAfterHeader() throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "5"]
        )!
        XCTAssertEqual(HTTPClient.defaultRetryDelay(response, attempt: 0), 5)
    }
}
