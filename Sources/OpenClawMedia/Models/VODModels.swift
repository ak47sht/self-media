import Foundation

// MARK: - VOD Search

struct VODSearchItem: Codable, Identifiable, Equatable {
    var id: String { vodID }
    let vodID: String
    let vodName: String
    let vodPic: String?
    let vodRemarks: String?
    let typeName: String?
    let vodYear: String?
    let vodArea: String?
    let vodActor: String?
    let vodDirector: String?

    enum CodingKeys: String, CodingKey {
        case vodID = "vod_id"
        case vodName = "vod_name"
        case vodPic = "vod_pic"
        case vodRemarks = "vod_remarks"
        case typeName = "type_name"
        case vodYear = "vod_year"
        case vodArea = "vod_area"
        case vodActor = "vod_actor"
        case vodDirector = "vod_director"
    }
}

struct VODSearchResponse: Decodable, Equatable {
    let list: [VODSearchItem]?
    let total: Int?
    let page: Int?
    let pagecount: Int?

    /// Some sources return `videos` instead of `list`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        list = try container.decodeIfPresent([VODSearchItem].self, forKey: .list)
            ?? container.decodeIfPresent([VODSearchItem].self, forKey: .videos)
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? list?.count
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        pagecount = try container.decodeIfPresent(Int.self, forKey: .pagecount) ?? 1
    }

    enum CodingKeys: String, CodingKey {
        case list, videos, total, page, pagecount
    }
}

// MARK: - VOD Detail

struct VODEpisode: Codable, Identifiable, Equatable {
    var id: String { "\(flag)-\(title)" }
    let flag: String
    let title: String
    let url: String
}

struct VODDetailItem: Codable, Identifiable, Equatable {
    var id: String { vodID }
    let vodID: String
    let vodName: String
    let vodPic: String?
    let vodRemarks: String?
    let typeName: String?
    let vodYear: String?
    let vodArea: String?
    let vodActor: String?
    let vodDirector: String?
    let vodContent: String?
    /// Source flags separated by `$$$`, e.g. "源1$$$源2"
    let vodPlayFrom: String?
    /// Episode URLs separated by `$$$` (flags) and `#` (episodes);
    /// each episode: "title$url"
    let vodPlayURL: String?

    /// Parsed episodes grouped by flag.
    var episodes: [VODEpisode] {
        guard let from = vodPlayFrom, let urls = vodPlayURL else { return [] }
        let flags = from.components(separatedBy: "$$$")
        let urlBlocks = urls.components(separatedBy: "$$$")
        var result: [VODEpisode] = []
        for (index, flag) in flags.enumerated() {
            guard index < urlBlocks.count else { break }
            let episodes = urlBlocks[index].components(separatedBy: "#")
            for ep in episodes where !ep.isEmpty {
                let parts = ep.components(separatedBy: "$")
                let title = parts.first ?? ep
                let url = parts.count > 1 ? parts.last! : ""
                result.append(VODEpisode(flag: flag, title: title, url: url))
            }
        }
        return result
    }

    enum CodingKeys: String, CodingKey {
        case vodID = "vod_id"
        case vodName = "vod_name"
        case vodPic = "vod_pic"
        case vodRemarks = "vod_remarks"
        case typeName = "type_name"
        case vodYear = "vod_year"
        case vodArea = "vod_area"
        case vodActor = "vod_actor"
        case vodDirector = "vod_director"
        case vodContent = "vod_content"
        case vodPlayFrom = "vod_play_from"
        case vodPlayURL = "vod_play_url"
    }
}

struct VODDetailResponse: Codable, Equatable {
    let list: [VODDetailItem]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        list = try container.decodeIfPresent([VODDetailItem].self, forKey: .list)
    }

    enum CodingKeys: String, CodingKey {
        case list
    }
}

// MARK: - VOD Play (resolved stream URL)

struct VODPlayResponse: Codable, Equatable {
    let url: String?
    let parse: Int?
    let extra: String?  // Some sources need extra parsing
    let header: String?
    let headers: [String: String]?
    let msg: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        parse = try container.decodeFlexibleIntIfPresent(forKey: .parse)
        extra = try container.decodeIfPresent(String.self, forKey: .extra)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
        msg = try container.decodeIfPresent(String.self, forKey: .msg)
    }

    var resolvedHeaders: [String: String] {
        var result = headers ?? [:]
        result.merge(StreamURLNormalizer.headers(from: header)) { _, new in new }
        return result
    }

    enum CodingKeys: String, CodingKey {
        case url, parse, extra, header, headers, msg
    }
}
