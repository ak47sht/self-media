import Foundation

struct VODSource: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let api: URL
    let type: Int
    let searchable: Bool
    let quickSearchable: Bool
    let playerType: Int?
    let ext: String?
}

struct TVBoxConfig: Codable, Equatable {
    let sources: [VODSource]
    let parsers: [String]
}

struct M3UPlaylistParser {
    func parseChannels(_ text: String, sourceName: String = "Imported M3U") -> [IPTVChannel] {
        var result: [IPTVChannel] = []
        var pendingName = "Channel"
        var pendingGroup = "Imported"
        var pendingLogo = ""
        var index = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line == "#EXTM3U" { continue }
            if line.hasPrefix("#EXTINF") {
                pendingName = parseTitle(line) ?? "Channel"
                pendingGroup = parseAttribute("group-title", from: line) ?? parseAttribute("group", from: line) ?? "Imported"
                pendingLogo = parseAttribute("tvg-logo", from: line) ?? ""
                continue
            }
            if line.hasPrefix("#") { continue }
            guard let url = URL(string: line), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { continue }
            let urlString = url.absoluteString
            let isHTTPS = scheme == "https"
            let isM3U8 = url.pathExtension.lowercased() == "m3u8"
            let browsable = isM3U8 || isHTTPS
            let route = IPTVRoute(
                url: urlString,
                playURL: urlString,
                sourceName: sourceName,
                group: pendingGroup,
                label: isHTTPS ? "HTTPS" : "HTTP",
                browserPlayable: browsable
            )
            result.append(IPTVChannel(
                name: pendingName,
                group: pendingGroup,
                logo: pendingLogo,
                sourceName: sourceName,
                url: urlString,
                playURL: urlString,
                browserPlayable: browsable,
                routes: [route],
                detailPath: ""
            ))
            index += 1
            pendingName = "Channel"
            pendingGroup = "Imported"
            pendingLogo = ""
        }
        return result
    }

    private func parseTitle(_ line: String) -> String? {
        guard let comma = line.lastIndex(of: ",") else { return nil }
        let title = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func parseAttribute(_ key: String, from line: String) -> String? {
        let pattern = key + "=\""
        guard let start = line.range(of: pattern) else { return nil }
        let tail = line[start.upperBound...]
        guard let end = tail.firstIndex(of: "\"") else { return nil }
        let value = String(tail[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct TVBoxConfigParser {
    func parse(_ data: Data) throws -> TVBoxConfig {
        let json = try JSONSerialization.jsonObject(with: stripJSONComments(data), options: [])
        guard let root = json as? [String: Any] else { return TVBoxConfig(sources: [], parsers: []) }
        let sites = root["sites"] as? [[String: Any]] ?? []
        let sources = sites.compactMap(parseSite)
        let parses = root["parses"] as? [[String: Any]] ?? []
        let parserNames = parses.compactMap { ($0["name"] as? String) ?? ($0["url"] as? String) }
        return TVBoxConfig(sources: sources, parsers: parserNames)
    }

    private func parseSite(_ site: [String: Any]) -> VODSource? {
        guard let key = site["key"] as? String,
              let name = site["name"] as? String,
              let apiString = site["api"] as? String,
              let api = URL(string: apiString) else { return nil }
        return VODSource(
            id: key,
            name: name,
            api: api,
            type: site["type"] as? Int ?? 0,
            searchable: (site["searchable"] as? Int ?? 1) != 0,
            quickSearchable: (site["quickSearch"] as? Int ?? 1) != 0,
            playerType: site["playerType"] as? Int,
            ext: site["ext"] as? String
        )
    }

    private func stripJSONComments(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        var output = ""
        var inString = false
        var escaped = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if escaped {
                output.append(c)
                escaped = false
            } else if c == "\\" {
                output.append(c)
                escaped = true
            } else if c == "\"" {
                output.append(c)
                inString.toggle()
            } else if !inString && c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                while i < chars.count && chars[i] != "\n" { i += 1 }
                if i < chars.count { output.append("\n") }
            } else {
                output.append(c)
            }
            i += 1
        }
        return Data(output.utf8)
    }
}
