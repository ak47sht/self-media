import Foundation

struct PlaybackRequest: Equatable {
    let url: URL
    let headers: [String: String]
    let label: String
    let reason: String
}

enum StreamURLNormalizer {
    static func normalize(_ rawValue: String?, inheritedHeaders: [String: String] = [:], label: String = "stream") -> PlaybackRequest? {
        guard var raw = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") { raw = "https:" + raw }

        var headers = inheritedHeaders
        let split = splitURLAndHeaders(raw)
        raw = split.url.trimmingCharacters(in: .whitespacesAndNewlines)
        headers.merge(split.headers) { _, new in new }

        guard let url = URL(string: raw) ?? URL(string: raw.removingPercentEncoding ?? raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return nil }

        return PlaybackRequest(url: url, headers: headers, label: label, reason: reason(for: url, headers: headers))
    }

    static func headers(from rawValue: String?) -> [String: String] {
        guard let raw = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return [:] }
        return parseHeaderPayload(raw)
    }

    static func serialize(_ request: PlaybackRequest) -> String {
        guard !request.headers.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: request.headers, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return request.url.absoluteString
        }
        return request.url.absoluteString + "|" + json
    }

    static func looksDirectlyPlayable(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.hasSuffix(".m3u8") || path.hasSuffix(".mp4") || path.hasSuffix(".mov") || path.hasSuffix(".m4v") || path.hasSuffix(".mp3") || path.hasSuffix(".aac") || path.hasSuffix(".flac") { return true }
        let value = url.absoluteString.lowercased()
        return value.contains("m3u8") || value.contains(".mp4") || value.contains(".mp3")
    }

    private static func splitURLAndHeaders(_ raw: String) -> (url: String, headers: [String: String]) {
        guard let separator = raw.firstIndex(of: "|") else { return (raw, [:]) }
        let urlPart = String(raw[..<separator])
        let headerPart = String(raw[raw.index(after: separator)...])
        return (urlPart, parseHeaderPayload(headerPart))
    }

    private static func parseHeaderPayload(_ payload: String) -> [String: String] {
        let clean = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return [:] }

        if let data = clean.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return normalizeHeaderDictionary(json)
        }

        var result: [String: String] = [:]
        let separators = CharacterSet(charactersIn: "&;")
        for pair in clean.components(separatedBy: separators) {
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = canonicalHeaderName(parts[0].removingPercentEncoding ?? parts[0])
            let value = parts[1].removingPercentEncoding ?? parts[1]
            if !key.isEmpty && !value.isEmpty { result[key] = value }
        }
        return result
    }

    private static func normalizeHeaderDictionary(_ json: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in json {
            if key.lowercased() == "headers", let nested = value as? [String: Any] {
                result.merge(normalizeHeaderDictionary(nested)) { _, new in new }
                continue
            }
            let name = canonicalHeaderName(key)
            if let stringValue = value as? String, !name.isEmpty, !stringValue.isEmpty {
                result[name] = stringValue
            }
        }
        return result
    }

    private static func canonicalHeaderName(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "ua", "user-agent", "user_agent": return "User-Agent"
        case "referer", "referrer": return "Referer"
        case "origin": return "Origin"
        case "cookie": return "Cookie"
        default: return trimmed
        }
    }

    private static func reason(for url: URL, headers: [String: String]) -> String {
        let kind = looksDirectlyPlayable(url) ? "direct media URL" : "resolved URL"
        return headers.isEmpty ? kind : "\(kind) with \(headers.count) header(s)"
    }
}

enum VODPlaybackResolver {
    static func resolve(response: VODPlayResponse, source: VODSource, episode: VODEpisode) -> [PlaybackRequest] {
        var inheritedHeaders = response.resolvedHeaders
        if inheritedHeaders.isEmpty {
            inheritedHeaders = StreamURLNormalizer.headers(from: source.ext)
        }

        var candidates: [PlaybackRequest] = []
        let rawValues = [response.url, response.extra, episode.url]
        for (index, raw) in rawValues.enumerated() {
            guard let request = StreamURLNormalizer.normalize(raw, inheritedHeaders: inheritedHeaders, label: label(for: index, response: response)) else { continue }
            candidates.append(request)
        }

        let direct = candidates.filter { StreamURLNormalizer.looksDirectlyPlayable($0.url) }
        let indirect = candidates.filter { !StreamURLNormalizer.looksDirectlyPlayable($0.url) }
        return dedupe(direct + indirect)
    }

    static func userMessage(for response: VODPlayResponse, candidates: [PlaybackRequest]) -> String {
        if !candidates.isEmpty { return "Resolved \(candidates.count) playback URL(s)." }
        if response.parse == 1 {
            return "This source requires parser/sniffer support and did not return a direct media URL yet. Try Open in IINA or another source."
        }
        return response.msg ?? "Source returned no playable URL."
    }

    private static func label(for index: Int, response: VODPlayResponse) -> String {
        switch index {
        case 0: return response.parse == 1 ? "parser result" : "play url"
        case 1: return "extra parser url"
        default: return "episode url"
        }
    }

    private static func dedupe(_ requests: [PlaybackRequest]) -> [PlaybackRequest] {
        var seen = Set<String>()
        return requests.filter { request in
            let key = request.url.absoluteString
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
}
