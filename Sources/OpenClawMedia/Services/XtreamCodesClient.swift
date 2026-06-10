import Foundation

enum XtreamCodesError: LocalizedError, Equatable {
    case missingBaseURL
    case missingUsername
    case missingPassword
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .missingBaseURL: return "Xtream source is missing a base URL."
        case .missingUsername: return "Xtream source is missing a username."
        case .missingPassword: return "Xtream source is missing a password."
        case .invalidURL: return "Xtream source URL could not be constructed."
        }
    }
}

struct XtreamCodesClient {
    let config: MediaSourceConfig
    var session: URLSession = .shared

    private let decoder = JSONDecoder()

    func playerAPIURL(action: String?, queryItems: [URLQueryItem] = []) throws -> URL {
        guard let baseURL = config.baseURL else { throw XtreamCodesError.missingBaseURL }
        guard let username = config.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else { throw XtreamCodesError.missingUsername }
        guard let password = config.password?.trimmingCharacters(in: .whitespacesAndNewlines), !password.isEmpty else { throw XtreamCodesError.missingPassword }

        let endpoint = baseURL.lastPathComponent == "player_api.php" ? baseURL : baseURL.appendingPathComponent("player_api.php")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw XtreamCodesError.invalidURL }
        var items = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
        ]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        items.append(contentsOf: queryItems)
        components.queryItems = items
        guard let url = components.url else { throw XtreamCodesError.invalidURL }
        return url
    }

    func liveCategories() async throws -> [XtreamCategory] {
        try await get(action: "get_live_categories")
    }

    func liveStreams(categoryID: String? = nil) async throws -> [XtreamLiveStream] {
        let query = categoryID.map { [URLQueryItem(name: "category_id", value: $0)] } ?? []
        return try await get(action: "get_live_streams", queryItems: query)
    }

    func vodCategories() async throws -> [XtreamCategory] {
        try await get(action: "get_vod_categories")
    }

    func vodStreams(categoryID: String? = nil) async throws -> [XtreamVODStream] {
        let query = categoryID.map { [URLQueryItem(name: "category_id", value: $0)] } ?? []
        return try await get(action: "get_vod_streams", queryItems: query)
    }

    func vodInfo(streamID: Int) async throws -> XtreamVODInfoResponse {
        try await get(action: "get_vod_info", queryItems: [URLQueryItem(name: "vod_id", value: String(streamID))])
    }

    private func get<T: Decodable>(action: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let url = try playerAPIURL(action: action, queryItems: queryItems)
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(T.self, from: data)
    }
}

struct XtreamCategory: Codable, Equatable {
    let categoryID: String
    let categoryName: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(String.self, forKey: .categoryID) {
            categoryID = id
        } else if let id = try container.decodeFlexibleIntIfPresent(forKey: .categoryID) {
            categoryID = String(id)
        } else {
            categoryID = ""
        }
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName) ?? "Xtream"
    }

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case categoryName = "category_name"
    }
}

struct XtreamLiveStream: Codable, Equatable {
    let name: String
    let streamID: Int
    let streamIcon: String?
    let categoryID: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Channel"
        streamID = try container.decodeFlexibleIntIfPresent(forKey: .streamID) ?? 0
        streamIcon = try container.decodeIfPresent(String.self, forKey: .streamIcon)
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case streamID = "stream_id"
        case streamIcon = "stream_icon"
        case categoryID = "category_id"
    }
}

struct XtreamVODStream: Codable, Equatable {
    let name: String
    let streamID: Int
    let streamIcon: String?
    let categoryID: String?
    let containerExtension: String?
    let rating: String?
    let year: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "VOD"
        streamID = try container.decodeFlexibleIntIfPresent(forKey: .streamID) ?? 0
        streamIcon = try container.decodeIfPresent(String.self, forKey: .streamIcon)
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID)
        containerExtension = try container.decodeIfPresent(String.self, forKey: .containerExtension)
        rating = try container.decodeIfPresent(String.self, forKey: .rating)
        year = try container.decodeIfPresent(String.self, forKey: .year)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case streamID = "stream_id"
        case streamIcon = "stream_icon"
        case categoryID = "category_id"
        case containerExtension = "container_extension"
        case rating
        case year
    }
}

struct XtreamVODInfoResponse: Codable, Equatable {
    let info: XtreamVODInfo?
    let movieData: XtreamVODMovieData?

    enum CodingKeys: String, CodingKey {
        case info
        case movieData = "movie_data"
    }
}

struct XtreamVODInfo: Codable, Equatable {
    let name: String?
    let movieImage: String?
    let plot: String?
    let genre: String?
    let releasedate: String?
    let rating: String?
    let cast: String?
    let director: String?

    enum CodingKeys: String, CodingKey {
        case name
        case movieImage = "movie_image"
        case plot
        case genre
        case releasedate
        case rating
        case cast
        case director
    }
}

struct XtreamVODMovieData: Codable, Equatable {
    let streamID: Int?
    let name: String?
    let categoryID: String?
    let containerExtension: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamID = try container.decodeFlexibleIntIfPresent(forKey: .streamID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID)
        containerExtension = try container.decodeIfPresent(String.self, forKey: .containerExtension)
    }

    enum CodingKeys: String, CodingKey {
        case streamID = "stream_id"
        case name
        case categoryID = "category_id"
        case containerExtension = "container_extension"
    }
}

enum XtreamCodesAdapter {
    static func liveChannels(from streams: [XtreamLiveStream], categories: [XtreamCategory], source: MediaSourceConfig) throws -> [IPTVChannel] {
        let namesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.categoryID, $0.categoryName) })
        return try streams.filter { $0.streamID > 0 }.map { stream in
            let url = try livePlaybackURL(streamID: stream.streamID, source: source).absoluteString
            let group = stream.categoryID.flatMap { namesByID[$0] } ?? "Xtream Live"
            let route = IPTVRoute(
                url: url,
                playURL: url,
                sourceName: source.name,
                group: group,
                label: "Xtream Live",
                browserPlayable: true
            )
            return IPTVChannel(
                name: stream.name,
                group: group,
                logo: stream.streamIcon ?? "",
                sourceName: source.name,
                url: url,
                playURL: url,
                browserPlayable: true,
                routes: [route],
                detailPath: "xtream://live/\(stream.streamID)"
            )
        }
    }

    static func vodSource(from source: MediaSourceConfig) throws -> VODSource {
        let api = try XtreamCodesClient(config: source).playerAPIURL(action: nil)
        return VODSource(
            id: source.id,
            name: source.name,
            api: api,
            type: 10,
            searchable: true,
            quickSearchable: true,
            playerType: nil,
            ext: "xtream"
        )
    }

    static func searchItems(from streams: [XtreamVODStream], categories: [XtreamCategory], query: String) -> [VODSearchItem] {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let namesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.categoryID, $0.categoryName) })
        return streams.filter { $0.streamID > 0 && (lowered.isEmpty || $0.name.lowercased().contains(lowered)) }.map { stream in
            VODSearchItem(
                vodID: "xtream:\(stream.streamID)",
                vodName: stream.name,
                vodPic: stream.streamIcon,
                vodRemarks: stream.rating,
                typeName: stream.categoryID.flatMap { namesByID[$0] },
                vodYear: stream.year,
                vodArea: nil,
                vodActor: nil,
                vodDirector: nil
            )
        }
    }

    static func detailItem(from response: XtreamVODInfoResponse, fallback: VODSearchItem, source: MediaSourceConfig) throws -> VODDetailItem {
        let streamID = numericID(from: fallback.vodID)
        let extensionValue = response.movieData?.containerExtension?.trimmingCharacters(in: .whitespacesAndNewlines)
        let containerExtension = extensionValue?.isEmpty == false ? extensionValue! : "mp4"
        let playURL = try vodPlaybackURL(streamID: streamID, containerExtension: containerExtension, source: source).absoluteString
        return VODDetailItem(
            vodID: fallback.vodID,
            vodName: response.info?.name ?? response.movieData?.name ?? fallback.vodName,
            vodPic: response.info?.movieImage ?? fallback.vodPic,
            vodRemarks: response.info?.rating ?? fallback.vodRemarks,
            typeName: response.info?.genre ?? fallback.typeName,
            vodYear: response.info?.releasedate ?? fallback.vodYear,
            vodArea: nil,
            vodActor: response.info?.cast ?? fallback.vodActor,
            vodDirector: response.info?.director ?? fallback.vodDirector,
            vodContent: response.info?.plot,
            vodPlayFrom: "Xtream",
            vodPlayURL: "Play$\(playURL)"
        )
    }

    static func directPlayResponse(for episode: VODEpisode) -> VODPlayResponse {
        VODPlayResponse(url: episode.url, parse: 0, extra: nil, header: nil, headers: nil, msg: nil)
    }

    static func numericID(from vodID: String) -> Int {
        Int(vodID.replacingOccurrences(of: "xtream:", with: "")) ?? 0
    }

    private static func livePlaybackURL(streamID: Int, source: MediaSourceConfig) throws -> URL {
        try streamURL(pathPrefix: "live", streamID: streamID, extensionValue: "m3u8", source: source)
    }

    private static func vodPlaybackURL(streamID: Int, containerExtension: String, source: MediaSourceConfig) throws -> URL {
        try streamURL(pathPrefix: "movie", streamID: streamID, extensionValue: containerExtension, source: source)
    }

    private static func streamURL(pathPrefix: String, streamID: Int, extensionValue: String, source: MediaSourceConfig) throws -> URL {
        guard let baseURL = source.baseURL else { throw XtreamCodesError.missingBaseURL }
        guard let username = source.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else { throw XtreamCodesError.missingUsername }
        guard let password = source.password?.trimmingCharacters(in: .whitespacesAndNewlines), !password.isEmpty else { throw XtreamCodesError.missingPassword }
        let streamBaseURL = baseURL.lastPathComponent == "player_api.php" ? baseURL.deletingLastPathComponent() : baseURL
        return streamBaseURL
            .appendingPathComponent(pathPrefix)
            .appendingPathComponent(username)
            .appendingPathComponent(password)
            .appendingPathComponent("\(streamID).\(extensionValue)")
    }
}
