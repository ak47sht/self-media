import SwiftUI
import MediaLibCore

/// VOD 视频详情视图
struct VODDetailView: View {
    @EnvironmentObject private var appState: AppState
    let video: VODVideo
    let source: MediaSource
    
    @State private var selectedRouteIndex: Int?
    
    private var routes: [VODPlayLine] {
        video.playURLs
    }
    
    var body: some View {
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
                            
                            Divider()
                            
                            Text("剧集 (\(selectedRoute.episodes.count))")
                                .font(.headline)
                            
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 80), spacing: 12)
                            ], spacing: 12) {
                                ForEach(Array(selectedRoute.episodes.enumerated()), id: \.offset) { index, episode in
                                    EpisodeButton(
                                        title: episode.name,
                                        index: index + 1
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
        .navigationTitle("视频详情")
        .onAppear {
            if selectedRouteIndex == nil && !routes.isEmpty {
                selectedRouteIndex = 0
            }
        }
    }
    
    private func playVideo(episode: VODEpisode, route: String) {
        // 使用多线路系统
        let playableMedia = MediaItemFactory.makePlayableMedia(
            from: video,
            episode: episode,
            allRoutes: video.playURLs
        )
        
        // TODO: 使用 PlayableMedia 支持多线路自动切换
        // 当前暂时使用第一条线路
        appState.play(playableMedia.currentItem)
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
