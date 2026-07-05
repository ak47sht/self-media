import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MediaLibCore

final class URLSourceHealthClassifierTests: XCTestCase {
    private func url(_ string: String = "https://example.com/video.mp4") -> URL {
        URL(string: string)!
    }

    private func httpResponse(status: Int, contentType: String?) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let contentType { headers["Content-Type"] = contentType }
        return HTTPURLResponse(url: url(), statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    func testClassifyClientErrorIsUnreachable() {
        XCTAssertEqual(URLSourceHealthClassifier.classify(httpResponse(status: 404, contentType: "video/mp4")), .unreachable)
    }

    func testClassifyServerErrorIsUnreachable() {
        XCTAssertEqual(URLSourceHealthClassifier.classify(httpResponse(status: 503, contentType: "video/mp4")), .unreachable)
    }

    func testClassifyHTMLIsUnparseable() {
        XCTAssertEqual(URLSourceHealthClassifier.classify(httpResponse(status: 200, contentType: "text/html; charset=utf-8")), .unparseable)
    }

    func testClassifyXHTMLIsUnparseable() {
        XCTAssertEqual(URLSourceHealthClassifier.classify(httpResponse(status: 200, contentType: "application/xhtml+xml")), .unparseable)
    }

    func testClassifyVideoIsOK() {
        XCTAssertEqual(URLSourceHealthClassifier.classify(httpResponse(status: 200, contentType: "video/mp4")), .ok)
    }

    func testClassifyOctetStreamIsOK() {
        XCTAssertEqual(URLSourceHealthClassifier.classify(httpResponse(status: 200, contentType: "application/octet-stream")), .ok)
    }

    func testClassifyNonHTTPResponseIsOK() {
        let response = URLResponse(url: url(), mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        XCTAssertEqual(URLSourceHealthClassifier.classify(response), .ok)
    }
}
