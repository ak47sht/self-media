import XCTest
import Foundation
@testable import MediaLibCore

final class BlockingIOExecutorAuditTests: XCTestCase {
    func testBlockingIORunsOffMainThreadAndReturnsValue() async throws {
        let result = await BlockingIOExecutor.run { () -> String in
            XCTAssertFalse(Thread.isMainThread)
            Thread.sleep(forTimeInterval: 0.05)
            return "IO_SUCCESS"
        }

        XCTAssertEqual(result, "IO_SUCCESS")
    }

    func testBlockingIOPropagatesErrorsAccurately() async {
        struct CustomIOError: Error, Equatable {}

        do {
            _ = try await BlockingIOExecutor.run {
                throw CustomIOError()
            }
            XCTFail("Expected CustomIOError")
        } catch let error as CustomIOError {
            XCTAssertEqual(error, CustomIOError())
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testConcurrentBlockingIOTasksExhaustSafelyWithoutDeadlock() async throws {
        let taskCount = 100
        let values = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for i in 0..<taskCount {
                group.addTask {
                    await BlockingIOExecutor.run {
                        i * 2
                    }
                }
            }

            var results: [Int] = []
            for await value in group {
                results.append(value)
            }
            return results
        }

        XCTAssertEqual(values.count, taskCount)
        XCTAssertEqual(Set(values), Set((0..<taskCount).map { $0 * 2 }))
    }
}
