import Combine
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MediaLibCore

/// URL 媒体链接的健康探测（可达性 / 可解析性）。
///
/// 当前只提供独立调度与结果存储，不主动接入 AppState/UI；本地 IPTV/VOD/TVBox 源的接线策略
/// 需要按各自协议单独设计，避免套用上游 URL 虚拟媒体源逻辑。
@MainActor
final class URLSourceHealthMonitor: ObservableObject {
    @Published private(set) var healthByID: [String: URLItemHealthState] = [:]

    private var task: Task<Void, Never>?
    private var refreshID = UUID()
    private let probe: @Sendable (URL) async -> URLItemHealthState

    init(probe: @escaping @Sendable (URL) async -> URLItemHealthState = URLSourceHealthMonitor.defaultProbe) {
        self.probe = probe
    }

    func state(for id: String) -> URLItemHealthState {
        healthByID[id] ?? .unknown
    }

    func reset() {
        task?.cancel()
        healthByID = [:]
    }

    func refresh(
        probeItems: [(id: String, url: URL)],
        liveIDs: Set<String>,
        onUpdated: @escaping @MainActor @Sendable () -> Void
    ) {
        task?.cancel()
        healthByID = healthByID.filter { liveIDs.contains($0.key) }
        guard !probeItems.isEmpty else { return }

        let currentRefresh = UUID()
        refreshID = currentRefresh
        for item in probeItems {
            healthByID[item.id] = .checking
        }

        let probe = self.probe
        task = Task.detached { [probeItems, currentRefresh, probe, onUpdated] in
            var results: [String: URLItemHealthState] = [:]
            await withTaskGroup(of: (String, URLItemHealthState).self) { group in
                for item in probeItems {
                    group.addTask {
                        (item.id, await probe(item.url))
                    }
                }
                for await pair in group {
                    results[pair.0] = pair.1
                }
            }

            await MainActor.run { [weak self] in
                guard let self, self.refreshID == currentRefresh else { return }
                for (id, state) in results {
                    self.healthByID[id] = state
                }
                onUpdated()
            }
        }
    }

    static func defaultProbe(_ url: URL) async -> URLItemHealthState {
        var head = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        head.httpMethod = "HEAD"
        if let response = try? await HTTPClient.shared.data(for: head).1 {
            return URLSourceHealthClassifier.classify(response)
        }

        var ranged = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        ranged.httpMethod = "GET"
        ranged.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        if let response = try? await HTTPClient.shared.data(for: ranged).1 {
            return URLSourceHealthClassifier.classify(response)
        }
        return .unreachable
    }
}
