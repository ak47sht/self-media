import SwiftUI
import MediaLibCore

/// IPTV 频道列表视图
struct IPTVChannelListView: View {
    @EnvironmentObject private var appState: AppState
    let source: MediaSource
    
    @State private var channels: [IPTVChannel] = []
    @State private var filteredChannels: [IPTVChannel] = []
    @State private var searchText = ""
    @State private var selectedGroup: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private var availableGroups: [String] {
        let groups = Set(channels.compactMap { $0.groupTitle })
        return groups.sorted()
    }
    
    private var displayChannels: [IPTVChannel] {
        var result = channels
        
        // 按分组筛选
        if let group = selectedGroup {
            result = result.filter { $0.groupTitle == group }
        }
        
        // 按搜索文本筛选
        if !searchText.isEmpty {
            result = result.filter { channel in
                channel.name.localizedCaseInsensitiveContains(searchText) ||
                (channel.groupTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack(spacing: 12) {
                // 搜索框
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索频道...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // 分组选择器
                if !availableGroups.isEmpty {
                    Menu {
                        Button("全部分组") {
                            selectedGroup = nil
                        }
                        Divider()
                        ForEach(availableGroups, id: \.self) { group in
                            Button(group) {
                                selectedGroup = group
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedGroup ?? "全部")
                                .font(.callout)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding()
            
            Divider()
            
            // 频道列表
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("加载频道列表...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text("加载失败")
                        .font(.headline)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重新加载") {
                        loadChannels()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if displayChannels.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "tv.slash" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "暂无频道" : "无匹配结果")
                        .font(.headline)
                    if !searchText.isEmpty {
                        Button("清除搜索") {
                            searchText = ""
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayChannels) { channel in
                            ChannelRow(channel: channel) {
                                playChannel(channel)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(source.name)
        .navigationSubtitle("\(displayChannels.count) 个频道")
        .onAppear {
            if channels.isEmpty {
                loadChannels()
            }
        }
    }
    
    private func loadChannels() {
        guard let db = appState.database else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let service = IPTVService(db: db)
                let loaded = try service.loadCachedChannels(sourceID: source.id)
                
                await MainActor.run {
                    self.channels = loaded
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func playChannel(_ channel: IPTVChannel) {
        DebugLog.log("IPTVChannelListView", "播放频道: \(channel.name) (共 \(channel.urls.count) 条线路)")
        guard let mediaItem = MediaItemFactory.makeMediaItem(from: channel, urlIndex: 0) else {
            DebugLog.log("IPTVChannelListView", "❌ 创建 MediaItem 失败: \(channel.name)")
            appState.alert = AppAlert(
                title: "无法播放",
                message: "频道 \(channel.name) 没有可用的播放地址"
            )
            return
        }
        appState.play(mediaItem)
    }
}

// MARK: - 频道行视图

private struct ChannelRow: View {
    let channel: IPTVChannel
    let onPlay: () -> Void
    
    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                // 频道 Logo
                if let logoURL = channel.logo, let url = URL(string: logoURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "tv")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "tv")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // 频道信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 8) {
                        if let group = channel.groupTitle {
                            Text(group)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if channel.urls.count > 1 {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text("\(channel.urls.count) 线路")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .padding(12)
            .background(Color.black.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Array Extension

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
