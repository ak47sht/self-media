import SwiftUI

@main
struct OpenClawMediaApp: App {
    private let config = ConfigLoader.load()

    var body: some Scene {
        WindowGroup {
            ContentView(config: config)
        }
    }
}

struct ContentView: View {
    let config: AppConfig

    var body: some View {
        if config.needsSetup {
            SetupView(config: config)
        } else {
            MediaHomeView(api: MediaAPI(config: config))
        }
    }
}

struct SetupView: View {
    let config: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(config.appName).font(.largeTitle.bold())
            Text("需要先配置你的 Movie/Music 服务域名。")
                .foregroundStyle(.secondary)
            Text("复制 config.example.json 为 config.local.json，或放到 ~/Library/Application Support/OpenClawMedia/config.json。")
                .font(.system(.body, design: .monospaced))
            Text("public repo 不包含真实 domain/token，这是预期行为。")
                .foregroundStyle(.orange)
        }
        .padding(28)
        .frame(minWidth: 620, minHeight: 360)
    }
}

struct MediaHomeView: View {
    @StateObject var api: MediaAPI
    @State private var channels: [IPTVChannel] = []
    @State private var songs: [Song] = []
    @State private var query = ""
    @State private var status = "Ready"

    var body: some View {
        NavigationSplitView {
            List {
                Section("Movie / IPTV") {
                    Button("加载 IPTV 频道") { Task { await loadChannels() } }
                    ForEach(channels.prefix(40)) { channel in
                        VStack(alignment: .leading) {
                            Text(channel.name).font(.headline)
                            Text([channel.group, channel.sourceName].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Music") {
                    TextField("搜索歌曲", text: $query)
                    Button("搜索") { Task { await searchSongs() } }
                    ForEach(songs.prefix(40)) { song in
                        VStack(alignment: .leading) {
                            Text(song.name).font(.headline)
                            Text(song.artist).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } detail: {
            VStack(spacing: 12) {
                Text("OpenClaw Media")
                    .font(.largeTitle.bold())
                Text(status)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 620)
    }

    private func loadChannels() async {
        do {
            let response = try await api.iptvChannels(query: "", showLimited: false)
            channels = response.channels
            status = "Loaded \(response.count) IPTV channels"
        } catch {
            status = "IPTV 加载失败：\(error.localizedDescription)"
        }
    }

    private func searchSongs() async {
        do {
            let response = try await api.searchSongs(query: query)
            songs = response.songs
            status = "Found \(response.count) songs"
        } catch {
            status = "音乐搜索失败：\(error.localizedDescription)"
        }
    }
}
