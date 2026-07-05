import Foundation

/// 阻塞式 I/O 的专用执行器。
///
/// Swift 并发的全局协作线程池宽度有限，且被阻塞的线程无法被抢占。全库文件存在性检查、
/// SQLite 全量读取、NAS 可达性探测这类长时间同步阻塞工作如果用 `Task.detached` 丢进协作池，
/// 会影响同池排队的轻量任务。此类工作应经这里的 GCD 队列执行。
public enum BlockingIOExecutor {
    private static let queue = DispatchQueue(
        label: "MediaLib.blockingIO",
        qos: .utility,
        attributes: .concurrent
    )

    /// 在专用队列上执行阻塞工作并 await 结果；调用方所在执行器只是挂起等待。
    public static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    /// 可抛错版本。
    public static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
