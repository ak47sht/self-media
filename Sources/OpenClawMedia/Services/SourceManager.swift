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
        for preset in presets {
            if let index = sources.firstIndex(where: { $0.id == preset.id }) {
                sources[index].name = preset.name
                sources[index].baseURL = preset.baseURL
                sources[index].capabilities = preset.capabilities
                refreshDiagnostics(for: index)
                if preset.id == "builtin-music-unlocked" {
                    sources[index].enabled = preset.enabled
                    refreshDiagnostics(for: index)
                }
                changed = true
            } else {
                sources.append(sourceWithDiagnostics(preset))
                changed = true
            }
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
            sources = decoded.map(sourceWithDiagnostics)
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

    func addSource(kind: MediaSourceKind, name: String, baseURLString: String, username: String? = nil, password: String? = nil) {
        let id = "source-\(UUID().uuidString.prefix(8))"
        let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespaces))
        let source = sourceWithDiagnostics(MediaSourceConfig(
            id: id,
            name: name,
            kind: kind,
            baseURL: baseURL,
            fileURL: nil,
            username: cleanOptional(username),
            password: cleanOptional(password),
            enabled: true,
            priority: (sources.map(\.priority).max() ?? 0) + 10,
            tags: [],
            capabilities: defaultCapabilities(for: kind)
        ))
        sources.append(source)
        save()
    }

    func removeSource(id: String) {
        sources.removeAll { $0.id == id }
        testResults.removeValue(forKey: id)
        save()
    }

    func updateSource(id: String, name: String? = nil, baseURLString: String? = nil, username: String? = nil, password: String? = nil, enabled: Bool? = nil, priority: Int? = nil) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        var src = sources[index]
        if let name { src.name = name }
        if let urlStr = baseURLString { src.baseURL = URL(string: urlStr) }
        if let username { src.username = cleanOptional(username) }
        if let password { src.password = cleanOptional(password) }
        if let enabled { src.enabled = enabled }
        if let priority { src.priority = priority }
        sources[index] = sourceWithDiagnostics(src)
        save()
    }

    func toggleSource(id: String) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].enabled.toggle()
        refreshDiagnostics(for: index)
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
        guard let source = sources.first(where: { $0.id == id }) else {
            testResults[id] = .init(success: false, message: "No source URL is configured yet.")
            updateHealth(id: id, status: .warning, message: "No source URL is configured yet.")
            return
        }

        let url: URL
        do {
            if source.kind == .xtreamCodes {
                url = try XtreamCodesClient(config: source).playerAPIURL(action: nil)
            } else if let baseURL = source.baseURL {
                url = baseURL
            } else if let fileURL = source.fileURL {
                url = fileURL
            } else {
                throw XtreamCodesError.missingBaseURL
            }
        } catch {
            testResults[id] = .init(success: false, message: error.localizedDescription)
            updateHealth(id: id, status: .warning, message: error.localizedDescription)
            return
        }

        let validation = SourceDiagnostics.validate(source)
        if validation.0 == .unsupported {
            testResults[id] = .init(success: false, message: validation.1.first?.message ?? "Source type is not supported in this build.")
            if let message = validation.1.first?.message {
                updateHealth(id: id, status: .unsupported, message: message)
            }
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
                    updateHealth(id: id, status: .ready, message: "Source responded successfully in \(elapsedMs)ms.")
                } else {
                    testResults[id] = .init(success: false, message: "Source responded with HTTP \(http.statusCode). Check the configured endpoint and source type.")
                    updateHealth(id: id, status: .failed, message: "Source responded with HTTP \(http.statusCode). Check the configured endpoint and source type.")
                }
            } else {
                testResults[id] = .init(success: true, message: "Reachable in \(elapsedMs)ms")
                updateHealth(id: id, status: .ready, message: "Source is reachable in \(elapsedMs)ms.")
            }
        } catch {
            testResults[id] = .init(success: false, message: "Source test failed: \(error.localizedDescription)")
            updateHealth(id: id, status: .failed, message: "Source test failed: \(error.localizedDescription)")
        }

        testingSourceID = nil
    }

    // MARK: - Helpers

    private func defaultCapabilities(for kind: MediaSourceKind) -> [SourceCapability] {
        SourceDiagnostics.defaultCapabilities(for: kind)
    }

    private func sourceWithDiagnostics(_ source: MediaSourceConfig) -> MediaSourceConfig {
        var value = source
        let validation = SourceDiagnostics.validate(value)
        value.validationStatus = validation.0
        value.diagnostics = validation.1
        return value
    }

    private func refreshDiagnostics(for index: Int) {
        sources[index] = sourceWithDiagnostics(sources[index])
    }

    private func updateHealth(id: String, status: SourceValidationStatus, message: String) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].validationStatus = status
        sources[index].diagnostics = [SourceDiagnostic(id: "connectivity", severity: status == .ready ? .info : .error, message: message)]
        save()
    }

    private func cleanOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SourceTestResult: Codable, Equatable {
    let success: Bool
    let message: String
}
