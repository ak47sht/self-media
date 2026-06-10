import SwiftUI
import AVKit
import AppKit

@main
struct OpenClawMediaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct ContentView: View {
    @State private var config = ConfigLoader.load()

    var body: some View {
        MediaHomeView(config: $config)
            .id(config.reloadIdentity)
    }
}

struct SetupView: View {
    let config: AppConfig

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()
            RadialGradient(colors: [AppTheme.blue.opacity(0.26), .clear], center: .topTrailing, startRadius: 20, endRadius: 560)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    AppIcon()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(config.appName)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("Native macOS media cockpit")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                Divider().overlay(AppTheme.hairline)

                Text("需要先配置 Movie / Music 服务域名")
                    .font(.system(size: 18, weight: .semibold))
                Text("public repo 不包含真实 domain 或 token。把示例配置复制成本地配置后，填入你自己的服务地址即可。")
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineSpacing(3)

                VStack(alignment: .leading, spacing: 12) {
                    SetupStep(number: "1", title: "复制模板", detail: "cp config.example.json config.local.json")
                    SetupStep(number: "2", title: "填写域名", detail: "movieBaseURL / musicBaseURL")
                    SetupStep(number: "3", title: "重新启动", detail: "OpenClaw Media 会自动读取本地配置")
                }

                HStack {
                    Label("Public-safe by default", systemImage: "lock.shield")
                        .foregroundStyle(AppTheme.green)
                    Spacer()
                    Text("config.local.json is ignored by git")
                        .foregroundStyle(AppTheme.mutedText)
                        .font(.system(size: 12, design: .monospaced))
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(width: 680)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AppTheme.hairline))
            .shadow(color: .black.opacity(0.34), radius: 34, y: 18)
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

struct MediaHomeView: View {
    @Binding var config: AppConfig
    @StateObject private var api: MediaAPI
    @StateObject private var playback = NativePlaybackManager()
    @StateObject private var store = LocalStore()
    @StateObject private var sourceManager = SourceManager()

    @State private var mode: MediaMode = .iptv
    @State private var sidebarSelection: SidebarSelection = .movie
    @State private var channels: [IPTVChannel] = []
    @State private var vodSources: [VODSource] = []
    @State private var songs: [Song] = []
    @State private var query = ""
    @State private var status = "Ready"
    @State private var selectedChannel: IPTVChannel?
    @State private var selectedRoute: IPTVRoute?
    @State private var selectedSong: Song?
    @State private var lyrics: LyricsResponse?

    private let m3uParser = M3UPlaylistParser()
    private let tvBoxParser = TVBoxConfigParser()

    init(config: Binding<AppConfig>) {
        _config = config
        _api = StateObject(wrappedValue: MediaAPI(config: config.wrappedValue))
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            RadialGradient(colors: [AppTheme.blue.opacity(0.18), .clear], center: .topLeading, startRadius: 80, endRadius: 700)
                .ignoresSafeArea()
            RadialGradient(colors: [AppTheme.green.opacity(0.10), .clear], center: .bottomTrailing, startRadius: 80, endRadius: 620)
                .ignoresSafeArea()

            HStack(spacing: 14) {
                Sidebar(selection: $sidebarSelection, mode: $mode, status: status, config: config)
                switch sidebarSelection {
                case .movie:
                    MovieDashboardView(channels: channels, vodSources: vodSources, config: config) {
                        sidebarSelection = .iptv
                        mode = .iptv
                    }
                case .vod:
                    VODView(api: api, playback: playback, store: store, sources: vodSources, xtreamSources: sourceManager.enabledSources(kind: .xtreamCodes), config: config)
                case .queue:
                    QueuePanel(store: store, playback: playback, playItem: playQueueItem)
                case .iptv, .music:
                    MainPanel(mode: $mode, query: $query, channels: channels, songs: songs, selectedChannel: $selectedChannel, selectedSong: $selectedSong, status: status, loadChannels: loadChannels, searchSongs: searchSongs, selectChannel: selectChannel, selectSong: selectSong)
                    DetailPanel(
                        mode: mode,
                        channel: selectedChannel,
                        selectedRoute: $selectedRoute,
                        song: selectedSong,
                        lyrics: lyrics,
                        playback: playback,
                        status: status,
                        store: store,
                        playChannel: playSelectedChannel,
                        playSong: playSelectedSong,
                        copyCurrentURL: copyCurrentURL,
                        openCurrentURLInIINA: openCurrentURLInIINA
                    )
                case .imageGen:
                    ImageGenView(config: config, sources: SourcePresets.defaultSources(config: config))
                case .settings:
                    ConfigurationCenterView(config: $config, sourceManager: sourceManager)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 1080, minHeight: 680)
        .task {
            sourceManager.seedDefaultSourcesIfNeeded(config: config)
            if channels.isEmpty { await loadChannels() }
            if vodSources.isEmpty { await loadVODSources() }
        }
        .onAppear {
            _ = establishMediaKeyboardShortcuts(playback)
        }
    }

    private func loadChannels() async {
        do {
            status = "Parsing IPTV channels…"
            var parsed: [IPTVChannel] = []
            if let iptvURL = config.iptvPlaylistURL {
                do {
                    let (data, _) = try await URLSession.shared.data(from: iptvURL)
                    guard let text = String(data: data, encoding: .utf8) else {
                        status = "IPTV source could not be parsed. Check that the configured URL returns a UTF-8 M3U playlist."
                        return
                    }
                    parsed = m3uParser.parseChannels(text, sourceName: iptvURL.lastPathComponent)
                } catch {
                    status = SourceDiagnostics.parsingFailure(kind: .iptvM3U, error: error)
                    return
                }
            }
            for source in sourceManager.enabledSources(kind: .xtreamCodes) {
                do {
                    let client = XtreamCodesClient(config: source)
                    let categories = try await client.liveCategories()
                    let streams = try await client.liveStreams()
                    parsed.append(contentsOf: try XtreamCodesAdapter.liveChannels(from: streams, categories: categories, source: source))
                } catch {
                    status = "Xtream live skipped for \(source.name): \(error.localizedDescription)"
                }
            }
            if parsed.isEmpty {
                // Fallback: try backend API if M3U URL not configured or empty
                status = "Loading IPTV channels from backend…"
                let response = try await api.iptvChannels(query: query, showLimited: false)
                parsed = response.channels
            }
            channels = parsed
            selectedChannel = parsed.first
            mode = .iptv
            status = "Loaded \(parsed.count) IPTV channels"
        } catch {
            status = SourceDiagnostics.parsingFailure(kind: .backendMovie, error: error)
        }
    }

    private func loadVODSources() async {
        let xtreamVOD = sourceManager.enabledSources(kind: .xtreamCodes).compactMap { try? XtreamCodesAdapter.vodSource(from: $0) }
        guard let feedURL = config.vodConfigURL ?? config.jsSourceImportURL ?? SourcePresets.builtinTVBoxFeed else {
            vodSources = xtreamVOD
            status = "Loaded \(vodSources.count) VOD sources"
            return
        }
        do {
            status = "Parsing VOD sources…"
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            let config = try tvBoxParser.parse(data)
            vodSources = config.sources.filter { $0.searchable } + xtreamVOD
            status = "Loaded \(vodSources.count) VOD sources"
        } catch {
            vodSources = xtreamVOD
            status = xtreamVOD.isEmpty ? SourceDiagnostics.parsingFailure(kind: .vodTVBox, error: error) : "Loaded \(xtreamVOD.count) Xtream VOD sources; TVBox parse failed: \(error.localizedDescription)"
        }
    }

    private func searchSongs() async {
        do {
            status = "Searching music…"
            let response = try await searchSongsAcrossSources(query: query)
            songs = response.songs
            selectedSong = response.songs.first
            lyrics = nil
            mode = .music
            status = "Found \(response.count) songs"
        } catch {
            status = "音乐搜索失败：\(error.localizedDescription)"
        }
    }

    private func searchSongsAcrossSources(query: String) async throws -> MusicSearchResponse {
        let enabled = sourceManager.enabledSources(kind: .backendMusic) + sourceManager.enabledSources(kind: .musicBuiltin)
        let bases = enabled.compactMap(\.baseURL)
        guard !bases.isEmpty else { return try await api.searchSongs(query: query) }

        var merged: [Song] = []
        var lastError: Error?
        for base in bases {
            do {
                let response = try await api.searchSongs(base: base, query: query)
                merged.append(contentsOf: response.songs)
            } catch {
                lastError = error
            }
        }
        if merged.isEmpty, let lastError { throw lastError }
        return MusicSearchResponse(songs: dedupeSongs(merged), count: merged.count, cache: nil, ncm_cache: nil)
    }

    private func dedupeSongs(_ values: [Song]) -> [Song] {
        var seen = Set<String>()
        return values.filter { song in
            let key = "\(song.source)|\(song.id)|\(song.name)|\(song.artist)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func selectChannel(_ channel: IPTVChannel) {
        selectedChannel = channel
        selectedRoute = channel.routes.first
        mode = .iptv
    }

    private func selectSong(_ song: Song) {
        selectedSong = song
        lyrics = nil
        mode = .music
    }

    private func playSelectedChannel() async {
        guard let channel = selectedChannel else { return }
        if selectedRoute == nil { selectedRoute = channel.routes.first }
        guard let resolved = PlaybackRouteResolver.resolve(channel: channel, selectedRoute: selectedRoute, allowHTTP: config.allowInsecureLocalhost) else {
            status = "没有可播放的视频 URL"
            return
        }
        let fallbacks = PlaybackRouteResolver.fallbackRoutes(for: channel, excluding: selectedRoute, allowHTTP: config.allowInsecureLocalhost)
        playback.play(url: resolved.url, title: channel.name, fallbacks: fallbacks)
        store.addToHistory(id: channel.name, type: .iptvChannel, title: channel.name, subtitle: channel.group, thumbnailURL: channel.logo.isEmpty ? nil : channel.logo, detailPath: nil)
        status = "原生播放：\(channel.name) · \(resolved.reason)"
    }

    private func playSelectedSong() async {
        guard let song = selectedSong else { return }
        do {
            status = "Resolving audio URL…"
            let response = try await resolvePlayURLAcrossSources(for: song)
            guard let value = response.url, let url = URL(string: value) else {
                status = response.error ?? "没有可播放的音乐 URL"
                return
            }
            playback.play(url: url, title: "\(song.name) — \(song.artist)")
            store.addToHistory(id: song.id, type: .musicSong, title: song.name, subtitle: song.artist, thumbnailURL: song.cover, detailPath: song.source)
            status = "原生播放：\(song.name)"
            Task { await loadLyrics(for: song) }
        } catch {
            status = SourceDiagnostics.playbackFailure(kind: .backendMusic, error: error)
        }
    }

    private func loadLyrics(for song: Song) async {
        do {
            lyrics = try await loadLyricsAcrossSources(for: song)
        } catch {
            // Lyrics are optional; keep playback running.
        }
    }

    private func resolvePlayURLAcrossSources(for song: Song) async throws -> PlayURLResponse {
        let bases = (sourceManager.enabledSources(kind: .backendMusic) + sourceManager.enabledSources(kind: .musicBuiltin)).compactMap(\.baseURL)
        guard !bases.isEmpty else { return try await api.playURL(for: song) }
        var lastError: Error?
        for base in bases {
            do {
                let response = try await api.playURL(base: base, for: song)
                if response.url != nil { return response }
                if response.error != nil { continue }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return PlayURLResponse(url: nil, provider: nil, error: "没有可播放的音乐 URL")
    }

    private func loadLyricsAcrossSources(for song: Song) async throws -> LyricsResponse {
        let bases = (sourceManager.enabledSources(kind: .backendMusic) + sourceManager.enabledSources(kind: .musicBuiltin)).compactMap(\.baseURL)
        guard !bases.isEmpty else { return try await api.lyrics(for: song) }
        var lastError: Error?
        for base in bases {
            do { return try await api.lyrics(base: base, for: song) }
            catch { lastError = error }
        }
        throw lastError ?? URLError(.badServerResponse)
    }

    private func copyCurrentURL() {
        guard let url = playback.nowPlayingURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        status = "已复制当前播放 URL"
    }

    private func openCurrentURLInIINA() {
        guard let url = playback.nowPlayingURL else {
            status = "请先播放或解析一个 URL"
            return
        }
        let iinaURL = URL(string: "iina://weblink?url=\(url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString)")!
        if NSWorkspace.shared.open(iinaURL) {
            status = "已发送到 IINA"
        } else {
            NSWorkspace.shared.open(url)
            status = "IINA 未响应，已用系统默认 App 打开 URL"
        }
    }

    private func playQueueItem(_ item: QueueItem) async {
        guard let raw = item.streamURL, let request = StreamURLNormalizer.normalize(raw, label: "queue") else {
            status = "队列项目没有可播放 URL，请从原页面重新解析。"
            return
        }
        playback.play(request: request, title: item.title)
        store.addToHistory(id: item.id, type: item.type, title: item.title, subtitle: item.subtitle, thumbnailURL: item.thumbnailURL, detailPath: item.detailPath)
        status = "队列播放：\(item.title)"
    }
}

enum MediaMode: String, CaseIterable, Identifiable {
    case iptv = "IPTV"
    case music = "Music"
    var id: String { rawValue }
}

enum SidebarSelection: String, CaseIterable, Identifiable {
    case movie = "Movie"
    case vod = "VOD"
    case iptv = "IPTV"
    case music = "Music"
    case queue = "Queue"
    case imageGen = "Image Gen"
    case settings = "Settings"
    var id: String { rawValue }
}

struct Sidebar: View {
    @Binding var selection: SidebarSelection
    @Binding var mode: MediaMode
    let status: String
    let config: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TrafficLights()
                .padding(.bottom, 2)

            HStack(spacing: 12) {
                AppIcon(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenClaw")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Personal Media Suite")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(.bottom, 6)

            QuickSearchRow()

            VStack(alignment: .leading, spacing: 6) {
                SidebarSectionTitle("APPS")
                SidebarItem(title: "Movie", subtitle: "影视聚合", icon: "film", active: selection == .movie) {
                    selection = .movie
                }
                SidebarItem(title: "IPTV", subtitle: "频道 / 线路", icon: "play.tv", active: selection == .iptv) {
                    selection = .iptv
                    mode = .iptv
                }
                SidebarItem(title: "VOD", subtitle: "影视搜索", icon: "play.rectangle.fill", active: selection == .vod) {
                    selection = .vod
                }
                SidebarItem(title: "Music", subtitle: "搜索 / 播放", icon: "music.note.list", active: selection == .music) {
                    selection = .music
                    mode = .music
                }
                SidebarItem(title: "Image Gen", subtitle: "AI 生图", icon: "sparkles", active: selection == .imageGen) {
                    selection = .imageGen
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SidebarSectionTitle("WORKFLOW")
                SidebarItem(title: "Queue", subtitle: "播放队列", icon: "text.line.first.and.arrowtriangle.forward", active: selection == .queue) {
                    selection = .queue
                }
                SidebarItem(title: "Settings", subtitle: "Sources", icon: "gearshape", active: selection == .settings) {
                    selection = .settings
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Label("Configured", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.green)
                Text(config.movieBaseURL.host ?? "movie.example.com")
                    .lineLimit(1)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(config.musicBaseURL.host ?? "music.example.com")
                    .lineLimit(1)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(2)
            }
            .font(.system(size: 12))
            .padding(14)
            .background(AppTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline))
        }
        .padding(18)
        .frame(width: 238)
        .background(AppTheme.sidebar, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct MovieDashboardView: View {
    let channels: [IPTVChannel]
    let vodSources: [VODSource]
    let config: AppConfig
    let openIPTV: () -> Void

    private let heroTags = ["继续看", "豆瓣热门", "IMDb Top 250", "高分", "科幻", "喜剧", "国产剧"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Movie Lite")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("选片、片源、IPTV 和最近播放都留在本地客户端；后端只做聚合与安全边界。")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Button(action: openIPTV) {
                    Label("Open IPTV", systemImage: "play.tv")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.purple)
            }

            HStack(spacing: 8) {
                ForEach(heroTags, id: \.self) { tag in
                    FilterChip(title: tag, active: tag == "继续看")
                }
            }

            HStack(spacing: 14) {
                FeatureCard(title: "继续观看", value: channels.first?.name ?? "等待 IPTV 数据", detail: "打开 App 后自动加载频道；后续接最近播放", icon: "play.rectangle.fill", tint: AppTheme.green)
                FeatureCard(title: "可用频道", value: "\(channels.count)", detail: "来自 Movie Lite 后端 normalized API", icon: "antenna.radiowaves.left.and.right", tint: AppTheme.blue)
                FeatureCard(title: "片源策略", value: "Direct", detail: "默认不代理流媒体；支持 IINA / Copy URL", icon: "arrow.up.forward.app", tint: AppTheme.purple)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Discovery layout", subtitle: "Figma Make → SwiftUI native translation")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    PosterPlaceholder(title: "豆瓣热门", subtitle: "Top picks", gradient: [AppTheme.purple, AppTheme.blue])
                    PosterPlaceholder(title: "IMDb 250", subtitle: "High score", gradient: [AppTheme.blue, AppTheme.green])
                    PosterPlaceholder(title: "最近播放", subtitle: "Continue", gradient: [AppTheme.green, AppTheme.amber])
                    PosterPlaceholder(title: "源管理", subtitle: config.movieBaseURL.host ?? "configured", gradient: [AppTheme.amber, AppTheme.purple])
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Next native functions", subtitle: "功能完善优先级")
                ChecklistRow(done: true, text: "Movie / IPTV / Music / Image Gen modules share one native shell")
                ChecklistRow(done: true, text: "Source provider model keeps weak-backend + strong-client architecture")
                ChecklistRow(done: false, text: "Movie detail API + source route switching")
                ChecklistRow(done: false, text: "Open in IINA / Copy stream URL actions")
            }
            .padding(14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline))

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct ImageGenView: View {
    let config: AppConfig
    let sources: [MediaSourceConfig]
    @StateObject private var api: MediaAPI
    @State private var prompt = ""
    @State private var negativePrompt = ""
    @State private var selectedModel = "Provider default"
    @State private var selectedSize = "1024×1024"
    @State private var selectedStyle = "Digital Art"
    @State private var advanced = false
    @State private var generationStatus = "Ready"
    @State private var generatedImageURL: URL?

    init(config: AppConfig, sources: [MediaSourceConfig]) {
        self.config = config
        self.sources = sources
        _api = StateObject(wrappedValue: MediaAPI(config: config))
    }

    private let models = ["Provider default", "FLUX.1 Pro", "Stable Diffusion XL", "DALL-E compatible", "Custom model ID"]
    private let sizes = ["512×512", "768×768", "1024×1024", "1024×768", "768×1024", "1920×1080"]
    private let styles = ["Photorealistic", "Anime", "Digital Art", "Sketch", "3D Render", "Pixel Art"]

    private var provider: MediaSourceConfig? {
        sources.first { $0.kind == .aiImageProvider }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Image Gen")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("客户端直连 provider；API key 只应保存在 Keychain，本仓库只保留占位配置。")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    ProviderBadge(source: provider)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Prompt")
                        .font(.system(size: 13, weight: .semibold))
                    TextEditor(text: $prompt)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 132)
                        .padding(10)
                        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.hairline))
                }

                HStack(spacing: 10) {
                    PickerCard(title: "Model", selection: $selectedModel, values: models)
                    PickerCard(title: "Size", selection: $selectedSize, values: sizes)
                    PickerCard(title: "Style", selection: $selectedStyle, values: styles)
                }

                DisclosureGroup(isExpanded: $advanced) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Negative prompt")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        TextEditor(text: $negativePrompt)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .frame(height: 74)
                            .padding(10)
                            .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        BadgeRow(items: ["Keychain secret", "Model configurable", "Client direct"])
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Advanced provider settings", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                }

                Button {
                    Task { await generateImage() }
                } label: {
                    Label("Generate image", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.purple)

                Text(generationStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))

            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Gallery", subtitle: generatedImageURL == nil ? "生成结果会显示在这里" : "Latest provider result")
                if let generatedImageURL {
                    AsyncImage(url: generatedImageURL) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline))
                    Button("Open image URL") { NSWorkspace.shared.open(generatedImageURL) }
                } else {
                    ForEach(0..<4, id: \.self) { index in
                        GeneratedImagePlaceholder(index: index, style: selectedStyle, size: selectedSize)
                    }
                }
                Spacer()
            }
            .padding(18)
            .frame(width: 330)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))
        }
    }

    private func generateImage() async {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else {
            generationStatus = "请输入 prompt。"
            return
        }
        guard config.aiImageProviderBaseURL != nil else {
            generationStatus = "请先在 Settings 配置 AI provider base URL。"
            return
        }
        generationStatus = "Generating image…"
        do {
            let response = try await api.generateImage(prompt: cleanPrompt, negativePrompt: negativePrompt, size: selectedSize)
            if let urlString = response.data.first?.url, let url = URL(string: urlString) {
                generatedImageURL = url
                generationStatus = "生成完成。"
            } else {
                generationStatus = "Provider 返回了结果，但没有 URL；b64_json 暂未展示。"
            }
        } catch {
            generationStatus = "生成失败：\(error.localizedDescription)"
        }
    }
}

struct MainPanel: View {
    @Binding var mode: MediaMode
    @Binding var query: String
    let channels: [IPTVChannel]
    let songs: [Song]
    @Binding var selectedChannel: IPTVChannel?
    @Binding var selectedSong: Song?
    let status: String
    let loadChannels: () async -> Void
    let searchSongs: () async -> Void
    let selectChannel: (IPTVChannel) -> Void
    let selectSong: (Song) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    ForEach(MediaMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.mutedText)
                    TextField(mode == .iptv ? "Search CCTV, sports, news…" : "Search songs, artists…", text: $query)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            Task {
                                if mode == .iptv {
                                    await loadChannels()
                                } else {
                                    await searchSongs()
                                }
                            }
                        }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 999, style: .continuous).stroke(AppTheme.hairline))

                Button {
                    Task {
                        if mode == .iptv {
                            await loadChannels()
                        } else {
                            await searchSongs()
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)
            }

            HStack(spacing: 8) {
                FilterChip(title: "All", active: true)
                FilterChip(title: mode == .iptv ? "HTTPS only" : "Playable")
                FilterChip(title: mode == .iptv ? "CCTV" : "Lyrics")
                FilterChip(title: mode == .iptv ? "Sports" : "Queue")
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if mode == .iptv {
                        ForEach(channels.prefix(80)) { channel in
                            ChannelRow(channel: channel, active: selectedChannel?.id == channel.id) {
                                selectChannel(channel)
                            }
                        }
                    } else {
                        ForEach(songs.prefix(80)) { song in
                            SongRow(song: song, active: selectedSong?.id == song.id) {
                                selectSong(song)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct EditableAppConfig {
    var appName: String
    var movieBaseURL: String
    var musicBaseURL: String
    var iptvPlaylistURL: String
    var vodConfigURL: String
    var jsSourceImportURL: String
    var previousMusicUnlockHash: String
    var aiImageProviderBaseURL: String
    var aiImageProviderModel: String
    var aiImageAPIKey: String
    var apiTimeoutSeconds: String
    var preferHTTPS: Bool
    var allowInsecureLocalhost: Bool

    init(config: AppConfig) {
        appName = config.appName
        movieBaseURL = config.movieBaseURL.absoluteString
        musicBaseURL = config.musicBaseURL.absoluteString
        iptvPlaylistURL = config.iptvPlaylistURL?.absoluteString ?? ""
        vodConfigURL = config.vodConfigURL?.absoluteString ?? ""
        jsSourceImportURL = config.jsSourceImportURL?.absoluteString ?? ""
        previousMusicUnlockHash = config.musicUnlockCodeHash
        aiImageProviderBaseURL = config.aiImageProviderBaseURL?.absoluteString ?? ""
        aiImageProviderModel = config.aiImageProviderModel
        aiImageAPIKey = config.aiImageAPIKey
        apiTimeoutSeconds = String(format: "%.0f", config.apiTimeoutSeconds)
        preferHTTPS = config.preferHTTPS
        allowInsecureLocalhost = config.allowInsecureLocalhost
    }

    func build(musicUnlockCode: String) -> AppConfig? {
        guard let movie = URL(string: movieBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let music = URL(string: musicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let iptv = iptvPlaylistURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(string: iptvPlaylistURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let vod = vodConfigURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(string: vodConfigURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let js = jsSourceImportURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(string: jsSourceImportURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let aiBase = aiImageProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(string: aiImageProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let rawUnlock = musicUnlockCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let unlockHash = rawUnlock.isEmpty ? previousMusicUnlockHash : AppConfig.sha256Hex(rawUnlock)
        return AppConfig(
            appName: appName.isEmpty ? "OpenClaw Media" : appName,
            movieBaseURL: movie,
            musicBaseURL: music,
            iptvPlaylistURL: iptv,
            vodConfigURL: vod,
            jsSourceImportURL: js,
            musicUnlockCodeHash: unlockHash,
            aiImageProviderBaseURL: aiBase,
            aiImageProviderModel: aiImageProviderModel.isEmpty ? "provider-default" : aiImageProviderModel,
            aiImageAPIKey: aiImageAPIKey,
            apiTimeoutSeconds: Double(apiTimeoutSeconds) ?? 15,
            preferHTTPS: preferHTTPS,
            allowInsecureLocalhost: allowInsecureLocalhost
        )
    }
}

struct ConfigurationCenterView: View {
    @Binding var config: AppConfig
    @ObservedObject var sourceManager: SourceManager
    @State private var draft: EditableAppConfig
    @State private var saveStatus = "Configuration is stored locally only."
    @State private var selectedTab = 0
    @State private var musicUnlockCode = ""
    @State private var updateStatus = "当前版本：\(AppUpdateChecker.currentVersionSummary)"
    @State private var latestRelease: AppUpdateRelease?
    @State private var isCheckingUpdate = false

    init(config: Binding<AppConfig>, sourceManager: SourceManager) {
        _config = config
        self.sourceManager = sourceManager
        _draft = State(initialValue: EditableAppConfig(config: config.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("导入源配置后 App 客户端解析播放，不需要后端服务。")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                HStack(spacing: 8) {
                    Picker("Tab", selection: $selectedTab) {
                        Text("Config").tag(0)
                        Text("Sources").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    Button("Save configuration") { save() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.purple)
                }
            }

            if selectedTab == 0 {
                configTabView
            } else {
                SourcesSettingsView(sourceManager: sourceManager)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))
    }

    private var configTabView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SourcePrincipleChip(title: "客户端本地解析", icon: "play.rectangle.on.rectangle")
                SourcePrincipleChip(title: "Keys stay local", icon: "key.fill")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("导入源配置")
                        .font(.system(size: 18, weight: .bold))

                    ConfigSection(title: "IPTV / M3U", subtitle: "App 直接解析 M3U 生成频道列表") {
                        ConfigTextField(title: "IPTV M3U 播放列表 URL", placeholder: "https://domain/playlist.m3u", text: $draft.iptvPlaylistURL)
                    }

                    ConfigSection(title: "VOD / TVBox", subtitle: "影视仓站点配置 (key/api JSON)，搜索/详情本地适配") {
                        ConfigTextField(title: "VOD config URL", placeholder: "tvbox config JSON URL", text: $draft.vodConfigURL)
                        ConfigTextField(title: "JS 源导入地址", placeholder: "可选自定义 JS 源适配器", text: $draft.jsSourceImportURL)
                    }

                    Text("音乐")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.top, 8)

                    ConfigSection(title: "Unlocked music backend", subtitle: "解锁后启用附加音乐 backend 能力；不是离线内置解析器") {
                        SecureConfigField(title: "Music unlock code", placeholder: config.isMusicUnlocked ? "已解锁；留空保持解锁" : "输入解锁码激活内置音乐源", text: $musicUnlockCode)
                        HStack(spacing: 8) {
                            Image(systemName: config.isMusicUnlocked ? "checkmark.seal.fill" : "lock.fill")
                                .foregroundStyle(config.isMusicUnlocked ? AppTheme.green : AppTheme.mutedText)
                            Text(config.isMusicUnlocked ? "附加音乐 backend 已解锁并启用" : "未解锁：只使用外部 Music backend")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(config.isMusicUnlocked ? AppTheme.green : AppTheme.mutedText)
                        }
                    }

                    ConfigSection(title: "App Updates", subtitle: "从 GitHub Release 下载最新 DMG，减少每次手动找包") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: latestRelease?.dmgAsset == nil ? "arrow.down.circle" : "checkmark.seal.fill")
                                    .foregroundStyle(latestRelease?.dmgAsset == nil ? AppTheme.mutedText : AppTheme.green)
                                Text(updateStatus)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(latestRelease?.dmgAsset == nil ? AppTheme.mutedText : AppTheme.green)
                            }
                            HStack(spacing: 10) {
                                Button(isCheckingUpdate ? "Checking…" : "Check latest DMG") {
                                    Task { await checkForUpdates() }
                                }
                                .disabled(isCheckingUpdate)
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.blue)

                                if let release = latestRelease, let asset = release.dmgAsset {
                                    Button("Download DMG") { NSWorkspace.shared.open(asset.browserDownloadURL) }
                                    Button("Open release page") { NSWorkspace.shared.open(release.htmlURL) }
                                }
                            }
                            Text("当前未做静默自安装：macOS 安全限制下仍需打开 DMG 后拖到 Applications，但不再需要每次去 Actions 里找 artifact。")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.mutedText)
                        }
                    }

                    Text("AI 生图")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.top, 8)

                    ConfigSection(title: "AI Image", subtitle: "客户端直连 AI provider") {
                        ConfigTextField(title: "AI provider base URL", placeholder: "https://api.provider.com/v1", text: $draft.aiImageProviderBaseURL)
                        ConfigTextField(title: "AI provider model", placeholder: "gpt-image-1 / flux / provider model id", text: $draft.aiImageProviderModel)
                        SecureConfigField(title: "AI provider API key", placeholder: "Keychain 存储，不会写进 JSON", text: $draft.aiImageAPIKey)
                    }

                    DisclosureGroup {
                        ConfigSection(title: "Advanced backend/debug settings", subtitle: "如果不想用客户端解析，可填自己的后端聚合服务") {
                            ConfigTextField(title: "Movie backend URL", placeholder: "https://domain/tools/movie-lite", text: $draft.movieBaseURL)
                            ConfigTextField(title: "Music backend URL", placeholder: "https://domain/tools/music-lite", text: $draft.musicBaseURL)
                        }
                        ConfigSection(title: "Runtime", subtitle: "Compatibility and network behavior") {
                            ConfigTextField(title: "App name", placeholder: "OpenClaw Media", text: $draft.appName)
                            ConfigTextField(title: "API timeout seconds", placeholder: "15", text: $draft.apiTimeoutSeconds)
                            Toggle("Prefer HTTPS", isOn: $draft.preferHTTPS)
                            Toggle("Allow insecure localhost", isOn: $draft.allowInsecureLocalhost)
                        }
                    } label: {
                        Label("Advanced backend/debug settings", systemImage: "gearshape.2")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.top, 12)
                }
                .padding(.vertical, 4)
            }

            Text(saveStatus)
                .font(.system(size: 12))
                .foregroundStyle(saveStatus.contains("Saved") ? AppTheme.green : AppTheme.mutedText)
                .padding(.top, 2)
        }
    }

    private func checkForUpdates() async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        do {
            let release = try await AppUpdateChecker.check()
            latestRelease = release
            if let asset = release.dmgAsset {
                let sizeMB = asset.size.map { String(format: "%.1f MB", Double($0) / 1_048_576.0) } ?? "size unknown"
                updateStatus = "Latest \(release.tagName)：\(asset.name) · \(sizeMB)"
            } else {
                updateStatus = "Latest \(release.tagName) found, but no DMG asset is attached yet."
            }
        } catch {
            latestRelease = nil
            updateStatus = "检查更新失败：\(error.localizedDescription)"
        }
    }

    private func save() {
        guard let next = draft.build(musicUnlockCode: musicUnlockCode) else {
            saveStatus = "Invalid URL. Please check Movie backend URL and Music backend URL."
            return
        }
        do {
            try ConfigStore.save(next)
            config = next
            sourceManager.seedDefaultSourcesIfNeeded(config: next)
            if let builtin = sourceManager.sources.first(where: { $0.id == "builtin-music-unlocked" }) {
                sourceManager.updateSource(id: builtin.id, enabled: next.isMusicUnlocked)
            }
            saveStatus = "Saved configuration to ~/Library/Application Support/OpenClawMedia/config.json. Restart is recommended after changing backend URLs."
        } catch {
            saveStatus = "Save failed: \(error.localizedDescription)"
        }
    }
}

struct ConfigSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(subtitle).font(.system(size: 12)).foregroundStyle(AppTheme.mutedText)
            }
            content
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct ConfigTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.secondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.hairline))
        }
    }
}

struct SecureConfigField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.secondaryText)
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.hairline))
        }
    }
}

struct SourcesSettingsView: View {
    @ObservedObject var sourceManager: SourceManager
    @State private var showingAddSheet = false
    @State private var newSourceName = ""
    @State private var newSourceURL = ""
    @State private var newSourceUsername = ""
    @State private var newSourcePassword = ""
    @State private var newSourceKind: MediaSourceKind = .iptvM3U
    @State private var editingSourceID: String? = nil
    @State private var editName = ""
    @State private var editURL = ""
    @State private var editUsername = ""
    @State private var editPassword = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sources")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Weak backend, strong local app. Manage and test your sources.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Button { showingAddSheet = true } label: {
                    Label("Add source", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)
            }

            HStack(spacing: 10) {
                SourcePrincipleChip(title: "Direct play locally", icon: "play.rectangle.on.rectangle")
                SourcePrincipleChip(title: "Backend normalized", icon: "server.rack")
                SourcePrincipleChip(title: "External player ready", icon: "arrow.up.forward.app")
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(sourceManager.sources.sorted { $0.priority < $1.priority }) { source in
                        SourceCard(source: source, testResult: sourceManager.testResults[source.id], isTesting: sourceManager.testingSourceID == source.id)
                            .contextMenu {
                                Button { sourceManager.toggleSource(id: source.id) } label: {
                                    Label(source.enabled ? "Disable" : "Enable", systemImage: source.enabled ? "xmark.circle" : "checkmark.circle")
                                }
                                Button { startEdit(source: source) } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button { Task { await sourceManager.testSource(id: source.id) } } label: {
                                    Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                                }
                                Divider()
                                Button(role: .destructive) { sourceManager.removeSource(id: source.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    if sourceManager.sources.isEmpty {
                        Text("No sources configured. Click \"Add source\" to get started.")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 20)
                    }
                }
                .padding(.vertical, 4)
            }

            Text("Secrets stay local. Sources are stored in app preferences, not in the public repo.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText)
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))
        .sheet(isPresented: $showingAddSheet) {
            addSourceSheet
        }
        .sheet(item: $editingSourceID) { id in
            editSourceSheet(id: id)
        }
    }

    // MARK: - Add Source Sheet

    private var addSourceSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Media Source")
                .font(.system(size: 20, weight: .semibold))
            Text("Add IPTV playlists, TVBox configs, music backends, or other compatible sources.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.secondaryText)

            Picker("Source type", selection: $newSourceKind) {
                Text("IPTV / M3U").tag(MediaSourceKind.iptvM3U)
                Text("Xtream Codes").tag(MediaSourceKind.xtreamCodes)
                Text("TVBox / VOD").tag(MediaSourceKind.vodTVBox)
                Text("Movie backend").tag(MediaSourceKind.backendMovie)
                Text("Music backend").tag(MediaSourceKind.backendMusic)
                Text("AI image provider").tag(MediaSourceKind.aiImageProvider)
            }
            .pickerStyle(.menu)

            ConfigTextField(title: "Name", placeholder: "My IPTV playlist", text: $newSourceName)
            ConfigTextField(title: "URL", placeholder: newSourceKind == .xtreamCodes ? "Provider base URL" : "https://example.com/playlist.m3u", text: $newSourceURL)
            if newSourceKind == .xtreamCodes {
                ConfigTextField(title: "Username", placeholder: "Xtream username", text: $newSourceUsername)
                SecureConfigField(title: "Password", placeholder: "Xtream password", text: $newSourcePassword)
            }

            HStack {
                Spacer()
                Button("Cancel") { showingAddSheet = false }
                    .buttonStyle(.bordered)
                Button("Add") {
                    sourceManager.addSource(kind: newSourceKind, name: newSourceName, baseURLString: newSourceURL, username: newSourceUsername, password: newSourcePassword)
                    newSourceName = ""
                    newSourceURL = ""
                    newSourceUsername = ""
                    newSourcePassword = ""
                    newSourceKind = .iptvM3U
                    showingAddSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.purple)
                .disabled(newSourceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    // MARK: - Edit Source Sheet

    private func editSourceSheet(id: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Source")
                .font(.system(size: 20, weight: .semibold))

            if let source = sourceManager.sources.first(where: { $0.id == id }) {
                Text(source.kind.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.blue)

                ConfigTextField(title: "Name", placeholder: source.name, text: $editName)
                    .onAppear {
                        editName = source.name
                        editURL = source.baseURL?.absoluteString ?? ""
                        editUsername = source.username ?? ""
                        editPassword = source.password ?? ""
                    }
                ConfigTextField(title: "URL", placeholder: source.endpointSummary, text: $editURL)
                if source.kind == .xtreamCodes {
                    ConfigTextField(title: "Username", placeholder: "Xtream username", text: $editUsername)
                    SecureConfigField(title: "Password", placeholder: "Xtream password", text: $editPassword)
                }

                HStack {
                    Text("Enabled")
                    Toggle("", isOn: Binding(
                        get: { source.enabled },
                        set: { sourceManager.updateSource(id: id, enabled: $0) }
                    ))
                }

                HStack {
                    Spacer()
                    Button("Cancel") { editingSourceID = nil }
                        .buttonStyle(.bordered)
                    Button("Save") {
                        sourceManager.updateSource(id: id, name: editName, baseURLString: editURL, username: editUsername, password: editPassword)
                        editingSourceID = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.purple)
                }
            } else {
                Text("Source not found.")
                Button("Close") { editingSourceID = nil }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func startEdit(source: MediaSourceConfig) {
        editName = source.name
        editURL = source.baseURL?.absoluteString ?? ""
        editUsername = source.username ?? ""
        editPassword = source.password ?? ""
        editingSourceID = source.id
    }
}

extension String: Identifiable {
    public var id: String { self }
}

struct SourcePrincipleChip: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.hairline))
    }
}

struct SourceCard: View {
    let source: MediaSourceConfig
    let testResult: SourceTestResult?
    let isTesting: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(source.enabled ? AppTheme.green.opacity(0.18) : AppTheme.surface)
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: iconName).foregroundStyle(source.enabled ? AppTheme.green : AppTheme.mutedText))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(source.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text(source.kind.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.blue.opacity(0.12), in: Capsule())
                    Spacer()
                    Text(isTesting ? "Testing" : source.validationStatus.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                Text(source.endpointSummary)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    ForEach(source.capabilities) { capability in
                        Text(capability.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(capability.enabled ? AppTheme.primaryText : AppTheme.mutedText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(AppTheme.elevated, in: Capsule())
                    }
                }

                if let testResult {
                    Text(testResult.message)
                        .font(.system(size: 11))
                        .foregroundStyle(testResult.success ? AppTheme.green : AppTheme.amber)
                        .lineLimit(2)
                } else if let diagnostic = source.diagnostics.first {
                    Text(diagnostic.message)
                        .font(.system(size: 11))
                        .foregroundStyle(diagnostic.severity == .error ? AppTheme.amber : AppTheme.mutedText)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline))
    }

    private var iconName: String {
        switch source.kind {
        case .backendMovie: return "play.tv"
        case .backendMusic: return "music.note.list"
        case .iptvM3U: return "list.bullet.rectangle"
        case .xtreamCodes: return "network"
        case .aiImageProvider: return "sparkles"
        case .openlist: return "externaldrive.connected.to.line.below"
        case .customParser: return "curlybraces"
        case .vodTVBox: return "play.rectangle"
        case .musicBuiltin: return "music.quarternote.3"
        }
    }

    private var statusColor: Color {
        if isTesting { return AppTheme.blue }
        switch source.validationStatus {
        case .ready: return AppTheme.green
        case .warning: return AppTheme.amber
        case .unsupported, .failed: return AppTheme.amber
        case .unknown: return AppTheme.mutedText
        }
    }
}

struct QueuePanel: View {
    @ObservedObject var store: LocalStore
    @ObservedObject var playback: NativePlaybackManager
    let playItem: (QueueItem) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Queue")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("可播放 URL 入队后可直接续播；没有 URL 的项目会提示回源重新解析。")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Button("Clear") { store.clearQueue() }
                    .buttonStyle(.bordered)
                    .disabled(store.queue.isEmpty)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.queue.sorted { $0.order < $1.order }) { item in
                        QueueRow(item: item) {
                            Task { await playItem(item) }
                        } remove: {
                            store.dequeue(item)
                        }
                    }
                    if store.queue.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                .font(.system(size: 42))
                                .foregroundStyle(AppTheme.mutedText.opacity(0.5))
                            Text("Queue is empty")
                                .font(.system(size: 18, weight: .semibold))
                            Text("在 VOD 详情或播放页把项目加入队列后，会出现在这里。")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.mutedText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                }
                .padding(.vertical, 4)
            }

            if playback.nowPlayingURL != nil {
                Text(playback.state.displayText)
                    .font(.system(size: 12))
                    .foregroundStyle(playback.state.isError ? AppTheme.amber : AppTheme.mutedText)
                PlaybackControlBar(playback: playback)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct QueueRow: View {
    let item: QueueItem
    let play: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .frame(width: 38, height: 38)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                Text(item.streamURL == nil ? "Needs resolve" : "Ready URL")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(item.streamURL == nil ? AppTheme.amber : AppTheme.green)
            }
            Spacer()
            Button("Play", action: play)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.green)
                .disabled(item.streamURL == nil)
            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.hairline))
    }

    private var iconName: String {
        switch item.type {
        case .iptvChannel: return "play.tv"
        case .musicSong: return "music.note"
        case .vodItem: return "play.rectangle.fill"
        }
    }
}

struct DetailPanel: View {
    let mode: MediaMode
    let channel: IPTVChannel?
    @Binding var selectedRoute: IPTVRoute?
    let song: Song?
    let lyrics: LyricsResponse?
    @ObservedObject var playback: NativePlaybackManager
    let status: String
    @ObservedObject var store: LocalStore
    let playChannel: () async -> Void
    let playSong: () async -> Void
    let copyCurrentURL: () -> Void
    let openCurrentURLInIINA: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .iptv ? "Now tuning" : "Now playing")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)

            VStack(alignment: .leading, spacing: 12) {
                NativePlayerSurface(player: playback.player, mode: mode, active: playback.nowPlayingURL != nil)

                if mode == .iptv, let channel {
                    HStack(alignment: .firstTextBaseline) {
                        Text(channel.name).font(.system(size: 24, weight: .semibold))
                        Spacer()
                        Button {
                            store.toggleFavorite(id: channel.name, type: .iptvChannel, title: channel.name, subtitle: channel.group, thumbnailURL: channel.logo.isEmpty ? nil : channel.logo, detailPath: nil)
                        } label: {
                            Image(systemName: store.isFavorite(id: channel.name, type: .iptvChannel) ? "heart.fill" : "heart")
                                .foregroundStyle(store.isFavorite(id: channel.name, type: .iptvChannel) ? AppTheme.amber : AppTheme.mutedText)
                        }
                        .buttonStyle(.plain)
                    }
                    Text([channel.group, channel.sourceName].filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(AppTheme.secondaryText)
                    BadgeRow(items: [channel.browserPlayable ? "Native playable" : "Limited", "\(channel.routes.count) routes"])
                    RouteList(routes: channel.routes, selectedRoute: $selectedRoute)
                    PlaybackActionRow(
                        primaryTitle: "Play video",
                        isPlaying: playback.isPlaying,
                        play: { Task { await playChannel() } },
                        pause: { playback.pause() },
                        resume: { playback.resume() },
                        stop: { playback.stop() },
                        copyURL: copyCurrentURL,
                        openInIINA: openCurrentURLInIINA
                    )
                } else if mode == .music, let song {
                    HStack(alignment: .firstTextBaseline) {
                        Text(song.name).font(.system(size: 24, weight: .semibold))
                        Spacer()
                        Button {
                            store.toggleFavorite(id: song.id, type: .musicSong, title: song.name, subtitle: song.artist, thumbnailURL: song.cover, detailPath: song.source)
                        } label: {
                            Image(systemName: store.isFavorite(id: song.id, type: .musicSong) ? "heart.fill" : "heart")
                                .foregroundStyle(store.isFavorite(id: song.id, type: .musicSong) ? AppTheme.amber : AppTheme.mutedText)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(song.artist).foregroundStyle(AppTheme.secondaryText)
                    BadgeRow(items: [song.source, song.duration ?? "unknown"])
                    PlaybackActionRow(
                        primaryTitle: "Play music",
                        isPlaying: playback.isPlaying,
                        play: { Task { await playSong() } },
                        pause: { playback.pause() },
                        resume: { playback.resume() },
                        stop: { playback.stop() },
                        copyURL: copyCurrentURL,
                        openInIINA: openCurrentURLInIINA
                    )
                    LyricsPreview(lyrics: lyrics)
                } else {
                    Text("Select an item")
                        .font(.system(size: 22, weight: .semibold))
                    Text(status).foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(16)
            .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))

            Text(playback.state.displayText)
                .font(.system(size: 12))
                .foregroundStyle(playback.state.isError ? AppTheme.amber : AppTheme.mutedText)
                .lineLimit(3)

            Text("Space play/pause · K stop · F fullscreen · M mute")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.mutedText)
                .opacity(0.6)

            if playback.state.isError {
                HStack(spacing: 8) {
                    Button("Try next route") { _ = playback.tryNextFallback() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.amber)
                        .controlSize(.small)
                    Button("Copy URL") { copyCurrentURL() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.top, 4)
            }

            if playback.nowPlayingURL != nil {
                PlaybackControlBar(playback: playback)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(18)
        .frame(width: 330)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct ChannelRow: View {
    let channel: IPTVChannel
    let active: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Circle().fill(channel.browserPlayable ? AppTheme.green : AppTheme.amber).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 5) {
                    Text(channel.name).font(.system(size: 14, weight: .semibold))
                    Text([channel.group, channel.sourceName].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(channel.routes.count) routes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                Image(systemName: "play.fill")
                    .foregroundStyle(active ? AppTheme.green : AppTheme.blue)
            }
            .padding(14)
            .background(active ? AppTheme.blue.opacity(0.16) : AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(active ? AppTheme.blue.opacity(0.42) : AppTheme.hairline))
        }
        .buttonStyle(.plain)
    }
}

struct SongRow: View {
    let song: Song
    let active: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10).fill(AppTheme.elevated).frame(width: 44, height: 44).overlay(Image(systemName: "music.note"))
                VStack(alignment: .leading, spacing: 5) {
                    Text(song.name).font(.system(size: 14, weight: .semibold))
                    Text([song.artist, song.album ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Text(song.source)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.green.opacity(0.12), in: Capsule())
                    .foregroundStyle(AppTheme.green)
                Image(systemName: "play.fill").foregroundStyle(active ? AppTheme.green : AppTheme.blue)
            }
            .padding(12)
            .background(active ? AppTheme.green.opacity(0.13) : AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(active ? AppTheme.green.opacity(0.36) : AppTheme.hairline))
        }
        .buttonStyle(.plain)
    }
}

struct RouteList: View {
    let routes: [IPTVRoute]
    @Binding var selectedRoute: IPTVRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routes").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.secondaryText)
            ForEach(routes.prefix(6)) { route in
                Button {
                    selectedRoute = route
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(route.label.isEmpty ? route.sourceName : route.label).lineLimit(1)
                            Text(route.playURL.isEmpty ? route.url : route.playURL)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(AppTheme.mutedText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(route.browserPlayable ? "Native" : "Try")
                            .foregroundStyle(route.browserPlayable ? AppTheme.green : AppTheme.amber)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .padding(10)
                    .background(selectedRoute?.id == route.id ? AppTheme.blue.opacity(0.16) : AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selectedRoute?.id == route.id ? AppTheme.blue.opacity(0.40) : AppTheme.hairline))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NativePlayerSurface: View {
    let player: AVPlayer
    let mode: MediaMode
    let active: Bool

    var body: some View {
        ZStack {
            if active {
                LegacyAVPlayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [AppTheme.blue.opacity(0.92), AppTheme.green.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: mode == .iptv ? "play.tv.fill" : "music.note")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(height: 178)
    }
}

struct LegacyAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}

struct PlaybackActionRow: View {
    let primaryTitle: String
    let isPlaying: Bool
    let play: () -> Void
    let pause: () -> Void
    let resume: () -> Void
    let stop: () -> Void
    let copyURL: () -> Void
    let openInIINA: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button {
                isPlaying ? pause() : play()
            } label: {
                Label(isPlaying ? "Pause" : primaryTitle, systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.green)

            HStack(spacing: 8) {
                Button("Resume", action: resume)
                Button("Stop", action: stop)
                Button("Copy URL", action: copyURL)
                Button("Open in IINA", action: openInIINA)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct LyricsPreview: View {
    let lyrics: LyricsResponse?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lyrics").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.secondaryText)
            if let lyrics, !lyrics.lines.isEmpty {
                ForEach(lyrics.lines.prefix(8)) { line in
                    Text(line.text)
                        .font(.system(size: 13))
                        .foregroundStyle(line.id == lyrics.lines.first?.id ? AppTheme.primaryText : AppTheme.mutedText)
                        .lineLimit(1)
                }
            } else if let lyrics, !lyrics.text.isEmpty {
                Text(lyrics.text)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(8)
            } else {
                Text("点击 Play music 后加载歌词。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(red: 1.0, green: 0.373, blue: 0.341)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 0.996, green: 0.737, blue: 0.180)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 0.157, green: 0.784, blue: 0.251)).frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }
}

struct QuickSearchRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
            Text("Quick search…")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
            Text("⌘K")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.mutedText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct SidebarSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(AppTheme.mutedText)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }
}

struct SidebarItem: View {
    let title: String
    var subtitle: String = ""
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(active ? AppTheme.secondaryText : AppTheme.mutedText)
                    }
                }
                Spacer()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? AppTheme.primaryText : AppTheme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(active ? AppTheme.purple.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(active ? AppTheme.purple.opacity(0.32) : .clear))
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText)
        }
    }
}

struct FeatureCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct PosterPlaceholder: View {
    let title: String
    let subtitle: String
    let gradient: [Color]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 142)
                .overlay(Image(systemName: "play.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(.white.opacity(0.88)))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(10)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct ChecklistRow: View {
    let done: Bool
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? AppTheme.green : AppTheme.mutedText)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(done ? AppTheme.primaryText : AppTheme.secondaryText)
            Spacer()
        }
    }
}

struct ProviderBadge: View {
    let source: MediaSourceConfig?
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
            VStack(alignment: .leading, spacing: 2) {
                Text(source?.name ?? "AI image provider")
                    .font(.system(size: 12, weight: .semibold))
                Text(source?.endpointSummary ?? "not configured")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .foregroundStyle(source?.enabled == true ? AppTheme.green : AppTheme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct PickerCard: View {
    let title: String
    @Binding var selection: String
    let values: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct GeneratedImagePlaceholder: View {
    let index: Int
    let style: String
    let size: String
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.purple.opacity(0.85), AppTheme.blue.opacity(0.65), AppTheme.green.opacity(0.42)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 76, height: 76)
                .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.82)))
            VStack(alignment: .leading, spacing: 5) {
                Text("Generation \(index + 1)")
                    .font(.system(size: 13, weight: .semibold))
                Text(style)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(size)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.mutedText)
            }
            Spacer()
        }
        .padding(10)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline))
    }
}

struct FilterChip: View {
    let title: String
    var active: Bool = false
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? AppTheme.primaryText : AppTheme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(active ? AppTheme.blue.opacity(0.20) : AppTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(active ? AppTheme.blue.opacity(0.36) : AppTheme.hairline))
    }
}

struct BadgeRow: View {
    let items: [String]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(items.filter { !$0.isEmpty }, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.surface, in: Capsule())
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

struct SetupStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(width: 28, height: 28)
                .background(AppTheme.blue.opacity(0.20), in: Circle())
                .foregroundStyle(AppTheme.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

struct AppIcon: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.blue, AppTheme.green], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: AppTheme.blue.opacity(0.30), radius: 16, y: 8)
    }
}

enum AppTheme {
    static let background = Color(red: 0.043, green: 0.051, blue: 0.063)
    static let panel = Color(red: 0.078, green: 0.091, blue: 0.114).opacity(0.94)
    static let surface = Color(red: 0.104, green: 0.122, blue: 0.153)
    static let elevated = Color(red: 0.128, green: 0.148, blue: 0.184)
    static let primaryText = Color(red: 0.962, green: 0.974, blue: 0.992)
    static let secondaryText = Color(red: 0.660, green: 0.690, blue: 0.742)
    static let mutedText = Color(red: 0.410, green: 0.444, blue: 0.502)
    static let hairline = Color.white.opacity(0.08)
    static let sidebar = Color(red: 0.031, green: 0.031, blue: 0.063).opacity(0.98)
    static let blue = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let purple = Color(red: 0.545, green: 0.361, blue: 0.965)
    static let green = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let amber = Color(red: 1.0, green: 0.839, blue: 0.039)
}
