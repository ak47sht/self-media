import SwiftUI

@main
struct OpenClawMediaApp: App {
    private let config = ConfigLoader.load()

    var body: some Scene {
        WindowGroup {
            ContentView(config: config)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct ContentView: View {
    let config: AppConfig

    var body: some View {
        if config.needsSetup {
            SetupView(config: config)
        } else {
            MediaHomeView(api: MediaAPI(config: config), config: config)
        }
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
    @StateObject private var api: MediaAPI
    let config: AppConfig

    @State private var mode: MediaMode = .iptv
    @State private var sidebarSelection: SidebarSelection = .iptv
    @State private var channels: [IPTVChannel] = []
    @State private var songs: [Song] = []
    @State private var query = ""
    @State private var status = "Ready"
    @State private var selectedChannel: IPTVChannel?
    @State private var selectedSong: Song?

    init(api: MediaAPI, config: AppConfig) {
        _api = StateObject(wrappedValue: api)
        self.config = config
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
                if sidebarSelection == .settings {
                    SourcesSettingsView(sources: SourcePresets.defaultSources(config: config))
                } else {
                    MainPanel(mode: $mode, query: $query, channels: channels, songs: songs, selectedChannel: $selectedChannel, selectedSong: $selectedSong, status: status, loadChannels: loadChannels, searchSongs: searchSongs)
                    DetailPanel(mode: mode, channel: selectedChannel, song: selectedSong, status: status)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 1080, minHeight: 680)
        .task {
            if channels.isEmpty { await loadChannels() }
        }
    }

    private func loadChannels() async {
        do {
            status = "Loading IPTV channels…"
            let response = try await api.iptvChannels(query: query, showLimited: false)
            channels = response.channels
            selectedChannel = response.channels.first
            mode = .iptv
            status = "Loaded \(response.count) IPTV channels"
        } catch {
            status = "IPTV 加载失败：\(error.localizedDescription)"
        }
    }

    private func searchSongs() async {
        do {
            status = "Searching music…"
            let response = try await api.searchSongs(query: query)
            songs = response.songs
            selectedSong = response.songs.first
            mode = .music
            status = "Found \(response.count) songs"
        } catch {
            status = "音乐搜索失败：\(error.localizedDescription)"
        }
    }
}

enum MediaMode: String, CaseIterable, Identifiable {
    case iptv = "IPTV"
    case music = "Music"
    var id: String { rawValue }
}

enum SidebarSelection: String, CaseIterable, Identifiable {
    case iptv = "IPTV"
    case music = "Music"
    case queue = "Queue"
    case settings = "Settings"
    var id: String { rawValue }
}

struct Sidebar: View {
    @Binding var selection: SidebarSelection
    @Binding var mode: MediaMode
    let status: String
    let config: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AppIcon(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenClaw")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Media")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(.bottom, 8)

            VStack(spacing: 8) {
                SidebarItem(title: "IPTV", icon: "play.tv", active: selection == .iptv) {
                    selection = .iptv
                    mode = .iptv
                }
                SidebarItem(title: "Music", icon: "music.note.list", active: selection == .music) {
                    selection = .music
                    mode = .music
                }
                SidebarItem(title: "Queue", icon: "text.line.first.and.arrowtriangle.forward", active: selection == .queue) {
                    selection = .queue
                }
                SidebarItem(title: "Settings", icon: "gearshape", active: selection == .settings) {
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))
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
                                selectedChannel = channel
                            }
                        }
                    } else {
                        ForEach(songs.prefix(80)) { song in
                            SongRow(song: song, active: selectedSong?.id == song.id) {
                                selectedSong = song
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

struct SourcesSettingsView: View {
    let sources: [MediaSourceConfig]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sources")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Weak backend, strong local app. Keep sources configurable and direct-played locally by default.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Button("Add source") {}
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
                    ForEach(sources.sorted { $0.priority < $1.priority }) { source in
                        SourceCard(source: source)
                    }
                }
                .padding(.vertical, 4)
            }

            Text("Secrets stay local. Public examples should never include private playlists, tokens, or VPS-only paths.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText)
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))
    }
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
                    Text(source.enabled ? "Enabled" : "Disabled")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(source.enabled ? AppTheme.green : AppTheme.mutedText)
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
        case .aiImageProvider: return "sparkles"
        case .openlist: return "externaldrive.connected.to.line.below"
        case .customParser: return "curlybraces"
        }
    }
}

struct DetailPanel: View {
    let mode: MediaMode
    let channel: IPTVChannel?
    let song: Song?
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .iptv ? "Now tuning" : "Now playing")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)

            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [AppTheme.blue.opacity(0.92), AppTheme.green.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: mode == .iptv ? "play.tv.fill" : "music.note")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(height: 178)

                if mode == .iptv, let channel {
                    Text(channel.name).font(.system(size: 24, weight: .semibold))
                    Text([channel.group, channel.sourceName].filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(AppTheme.secondaryText)
                    BadgeRow(items: [channel.browserPlayable ? "Native playable" : "Limited", "\(channel.routes.count) routes"])
                    RouteList(routes: channel.routes)
                } else if mode == .music, let song {
                    Text(song.name).font(.system(size: 24, weight: .semibold))
                    Text(song.artist).foregroundStyle(AppTheme.secondaryText)
                    BadgeRow(items: [song.source, song.duration ?? "unknown"])
                    PlayerControls()
                    LyricsPreview()
                } else {
                    Text("Select an item")
                        .font(.system(size: 22, weight: .semibold))
                    Text(status).foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(16)
            .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))

            Spacer()
        }
        .padding(18)
        .frame(width: 330, maxHeight: .infinity)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routes").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.secondaryText)
            ForEach(routes.prefix(4)) { route in
                HStack {
                    Text(route.label).lineLimit(1)
                    Spacer()
                    Text(route.browserPlayable ? "HTTPS" : "Limited")
                        .foregroundStyle(route.browserPlayable ? AppTheme.green : AppTheme.amber)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

struct PlayerControls: View {
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "backward.fill")
            Image(systemName: "play.circle.fill").font(.system(size: 38)).foregroundStyle(AppTheme.green)
            Image(systemName: "forward.fill")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

struct LyricsPreview: View {
    private let lines = ["歌词会在这里按时间滚动", "当前行高亮显示", "保持可读，不显示终端感原文"]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lyrics").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.secondaryText)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(line == lines.first ? AppTheme.primaryText : AppTheme.mutedText)
            }
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SidebarItem: View {
    let title: String
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? AppTheme.primaryText : AppTheme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(active ? AppTheme.blue.opacity(0.18) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
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
    static let blue = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let green = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let amber = Color(red: 1.0, green: 0.839, blue: 0.039)
}
