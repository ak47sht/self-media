import SwiftUI
import MediaLibCore

/// VOD 视频详情视图
struct VODDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let video: VODVideo
    let source: MediaSource
    
    @State private var selectedRouteIndex: Int?
    @State private var episodePage = 0  // 剧集分页，每页 50 集
    
    private let episodesPerPage = 50
    
    var body: some View {
        // 预计算，避免 body 内重复访问计算属性
        let routes = video.playURLs
        
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                // 海报和基本信息
                HStack(alignment: .top, spacing: 20) {
                    // 海报
                    if let picURL = video.pic, let url = URL(string: picURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(2/3, contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.black.opacity(0.2))
                                .overlay {
                                    ProgressView()
                                }
                        }
                        .frame(width: 200, height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 8)
                    }
                    
                    // 基本信息
                    VStack(alignment: .leading, spacing: 12) {
                        Text(video.name)
                            .font(.title2.weight(.bold))
                        
                        if let type = video.type {
                            Label(type, systemImage: "film")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let year = video.year {
                            Label(year, systemImage: "calendar")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let area = video.area {
                            Label(area, systemImage: "globe")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let lang = video.lang {
                            Label(lang, systemImage: "speaker.wave.2")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                Divider()
                
                // 演员和导演
                if let actors = video.actors, !actors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("演员")
                            .font(.headline)
                        Text(actors)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let director = video.director, !director.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("导演")
                            .font(.headline)
                        Text(director)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 简介
                if let content = video.content, !content.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("简介")
                            .font(.headline)
                        Text(content)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                // 播放线路
                VStack(alignment: .leading, spacing: 12) {
                    Text("播放线路 (\(routes.count))")
                        .font(.headline)
                    
                    if routes.isEmpty {
                        Text("暂无播放线路")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 100), spacing: 12)
                        ], spacing: 12) {
                            ForEach(Array(routes.enumerated()), id: \.offset) { index, route in
                                RouteButton(
                                    route: route.name,
                                    isSelected: selectedRouteIndex == index,
                                    episodeCount: route.episodes.count
                                ) {
                                    selectedRouteIndex = index
                                }
                            }
                        }
                        
                        // 选中线路的剧集列表
                        if let selectedIndex = selectedRouteIndex,
                           selectedIndex < routes.count {
                            let selectedRoute = routes[selectedIndex]
                            let totalEpisodes = selectedRoute.episodes.count
                            
                            Divider()
                            
                            HStack {
                                Text("剧集 (\(totalEpisodes))")
                                    .font(.headline)
                                
                                Spacer()
                                
                                // 分页控制（仅当剧集超过 episodesPerPage 时显示）
                                if totalEpisodes > episodesPerPage {
                                    let totalPages = (totalEpisodes + episodesPerPage - 1) / episodesPerPage
                                    let startEp = episodePage * episodesPerPage + 1
                                    let endEp = min((episodePage + 1) * episodesPerPage, totalEpisodes)
                                    
                                    HStack(spacing: 12) {
                                        Button {
                                            if episodePage > 0 {
                                                episodePage -= 1
                                            }
                                        } label: {
                                            Image(systemName: "chevron.left")
                                                .font(.caption)
                                        }
                                        .disabled(episodePage == 0)
                                        .buttonStyle(.plain)
                                        
                                        Text("\(startEp)-\(endEp)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Button {
                                            if episodePage < totalPages - 1 {
                                                episodePage += 1
                                            }
                                        } label: {
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                        }
                                        .disabled(episodePage >= totalPages - 1)
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            
                            // 计算当前页的剧集范围
                            let startIndex = episodePage * episodesPerPage
                            let endIndex = min(startIndex + episodesPerPage, totalEpisodes)
                            let pageEpisodes = Array(selectedRoute.episodes[startIndex..<endIndex])
                            
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 80), spacing: 12)
                            ], spacing: 12) {
                                ForEach(Array(pageEpisodes.enumerated()), id: \.offset) { pageIndex, episode in
                                    let actualIndex = startIndex + pageIndex
                                    EpisodeButton(
                                        title: episode.name,
                                        index: actualIndex + 1
                                    ) {
                                        playVideo(episode: episode, route: selectedRoute.name)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        
        // 关闭按钮（右上角）
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 32, height: 32)
                )
        }
        .buttonStyle(.plain)
        .padding(20)
    }
        .navigationTitle("视频详情")
        .onAppear {
            DebugLog.log("VODDetailView", "打开详情页")
            DebugLog.log("VODDetailView", "  视频: \(video.name)")
            DebugLog.log("VODDetailView", "  线路数: \(routes.count)")
            if !routes.isEmpty {
                let episodeCounts = routes.map { $0.episodes.count }
                DebugLog.log("VODDetailView", "  各线路剧集数: \(episodeCounts)")
            }
        }
        .task {
            if selectedRouteIndex == nil && !routes.isEmpty {
                selectedRouteIndex = 0
                DebugLog.log("VODDetailView", "  自动选择第一条线路")
            }
        }
        .onChange(of: selectedRouteIndex) { newIdx in
            if let newIdx = newIdx, newIdx < routes.count {
                let route = routes[newIdx]
                DebugLog.log("VODDetailView", "切换线路: \(route.name) (共 \(route.episodes.count) 集)")
            }
            episodePage = 0
        }
        .onChange(of: episodePage) { newValue in
            if let idx = selectedRouteIndex, idx < routes.count {
                let totalEps = routes[idx].episodes.count
                let startEp = newValue * episodesPerPage + 1
                let endEp = min((newValue + 1) * episodesPerPage, totalEps)
                DebugLog.log("VODDetailView", "剧集分页: 第 \(newValue + 1) 页 (\(startEp)-\(endEp) / \(totalEps))")
            }
        }
    }
    
    private func playVideo(episode: VODEpisode, route: String) {
        DebugLog.log("VODDetailView", "▶️ 开始播放")
        DebugLog.log("VODDetailView", "  视频: \(video.name)")
        DebugLog.log("VODDetailView", "  剧集: \(episode.name)")
        DebugLog.log("VODDetailView", "  线路: \(route)")
        DebugLog.log("VODDetailView", "  URL: \(episode.url)")
        
        // 创建 MediaItem 并播放
        let mediaItem = MediaItemFactory.makeMediaItem(from: video, episode: episode, sourceName: source.name)
        DebugLog.log("VODDetailView", "  MediaItem 已创建: \(mediaItem.title)")
        DebugLog.log("VODDetailView", "  MediaItem.sourcePath: \(mediaItem.sourcePath)")
        DebugLog.log("VODDetailView", "  MediaItem.filePath: \(mediaItem.filePath)")
        
        appState.play(mediaItem)
        DebugLog.log("VODDetailView", "  已调用 appState.play()")
    }
}

// MARK: - 线路按钮

private struct RouteButton: View {
    let route: String
    let isSelected: Bool
    let episodeCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(route)
                    .font(.callout.weight(.medium))
                Text("\(episodeCount) 集")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? Color.blue
                    : Color.black.opacity(0.2)
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 剧集按钮

private struct EpisodeButton: View {
    let title: String
    let index: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title.isEmpty ? "第\(index)集" : title)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.2))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
