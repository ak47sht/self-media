import Foundation

/// Manages media sources: add, remove, edit, enable/disable, test connectivity.
/// Sources are persisted as part of AppConfig.
@MainActor
final class SourceManager: ObservableObject {
    @Published var sources: [MediaSourceConfig] = []
    @Published var testingSourceID: String? = nil
    @Published var testResults: [String: SourceTestResult] = [:]

    private let defaults = UserDefaults.standard
    private let sourceKey = "com.openclaw.media.sources"

    init() {
        load()
    }

    func seedDefaultSourcesIfNeeded(config: AppConfig) {
        let presets = SourcePresets.defaultSources(config: config)
        if sources.isEmpty {
            sources = presets
            save()
            return
        }

        var changed = false
        for preset in presets where !sources.contains(where: { $0.id == preset.id }) {
            sources.append(preset)
            changed = true
        }
        if changed { save() }
    }

    func enabledSources(kind: MediaSourceKind) -> [MediaSourceConfig] {
        sources
            .filter { $0.kind == kind && $0.enabled }
            .sorted { $0.priority < $1.priority }
    }

    // MARK: - Load / Save

    func load() {
        if let data = defaults.data(forKey: sourceKey),
           let decoded = try? JSONDecoder().decode([MediaSourceConfig].self, from: data) {
            sources = decoded
        } else {
            sources = []
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(sources) {
            defaults.set(data, forKey: sourceKey)
        }
    }

    // MARK: - CRUD

    func addSource(kind: MediaSourceKind, name: String, baseURLString: String) {
        let id = "source-\(UUID().uuidString.prefix(8))"
        let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespaces))
        let source = MediaSourceConfig(
            id: id,
            name: name,
            kind: kind,
            baseURL: baseURL,
            fileURL: nil,
            enabled: true,
            priority: (sources.map(\.priority).max() ?? 0) + 10,
            tags: [],
            capabilities: defaultCapabilities(for: kind)
        )
        sources.append(source)
        save()
    }

    func removeSource(id: String) {
        sources.removeAll { $0.id == id }
        testResults.removeValue(forKey: id)
        save()
    }

    func updateSource(id: String, name: String? = nil, baseURLString: String? = nil, enabled: Bool? = nil, priority: Int? = nil) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        var src = sources[index]
        if let name { src.name = name }
        if let urlStr = baseURLString { src.baseURL = URL(string: urlStr) }
        if let enabled { src.enabled = enabled }
        if let priority { src.priority = priority }
        sources[index] = src
        save()
    }

    func toggleSource(id: String) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].enabled.toggle()
        save()
    }

    func moveSource(from source: IndexSet, to destination: Int) {
        sources.move(fromOffsets: source, toOffset: destination)
        // Re-prioritize
        for i in sources.indices { sources[i].priority = i * 10 }
        save()
    }

    // MARK: - Test

    func testSource(id: String) async {
        guard let source = sources.first(where: { $0.id == id }),
              let url = source.baseURL else {
            testResults[id] = .init(success: false, message: "No URL configured")
            return
        }

        testingSourceID = id
        let start = Date()

        do {
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.httpMethod = "HEAD"
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            if let http = response as? HTTPURLResponse {
                if (200..<400).contains(http.statusCode) {
                    testResults[id] = .init(success: true, message: "OK — \(http.statusCode) in \(elapsedMs)ms")
                } else {
                    testResults[id] = .init(success: false, message: "HTTP \(http.statusCode)")
                }
            } else {
                testResults[id] = .init(success: true, message: "Reachable in \(elapsedMs)ms")
            }
        } catch {
            testResults[id] = .init(success: false, message: error.localizedDescription)
        }

        testingSourceID = nil
    }

    // MARK: - Helpers

    private func defaultCapabilities(for kind: MediaSourceKind) -> [SourceCapability] {
        switch kind {
        case .backendMovie:
            return [
                SourceCapability(name: "Search", enabled: false),
                SourceCapability(name: "Direct play locally", enabled: true),
                SourceCapability(name: "External player ready", enabled: true),
            ]
        case .backendMusic:
            return [
                SourceCapability(name: "Search", enabled: true),
                SourceCapability(name: "Direct play locally", enabled: true),
                SourceCapability(name: "Lyrics", enabled: true),
            ]
        case .iptvM3U:
            return [
                SourceCapability(name: "Direct play locally", enabled: true),
                SourceCapability(name: "External player ready", enabled: true),
            ]
        case .vodTVBox:
            return [
                SourceCapability(name: "Search", enabled: true),
                SourceCapability(name: "Detail", enabled: true),
                SourceCapability(name: "Direct play locally", enabled: true),
            ]
        case .aiImageProvider:
            return [
                SourceCapability(name: "Provider/API request", enabled: true),
                SourceCapability(name: "Keychain secret", enabled: true),
                SourceCapability(name: "Model configurable", enabled: true),
            ]
        case .musicBuiltin:
            return [
                SourceCapability(name: "Search", enabled: false),
                SourceCapability(name: "Direct play locally", enabled: true),
                SourceCapability(name: "Unlock required", enabled: true),
            ]
        case .openlist:
            return [
                SourceCapability(name: "Local library", enabled: true),
            ]
        case .customParser:
            return [
                SourceCapability(name: "Custom parser", enabled: false),
            ]
        }
    }
}

struct SourceTestResult: Codable, Equatable {
    let success: Bool
    let message: String
}
