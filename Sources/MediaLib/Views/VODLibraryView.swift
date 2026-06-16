import SwiftUI
import MediaLibCore

/// VOD 视频库视图（支持分页加载）
struct VODLibraryView: View {
    @EnvironmentObject private var appState: AppState
    let source: MediaSource
    
    @State private var videos: [VODVideo] = []
    @State private var searchText = ""
    @State private var selectedType: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    // 分页状态
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    
    @State private var selectedVideo: VODVideo?
    @State private var showingVideoDetail = false
    
    private var types: [String] {
        let allTypes = videos.compactMap { $0.type }.uniqued()
        return allTypes.sorted()
    }
    
    private var displayVideos: [VODVideo] {
        var result = videos
        
        // 按类型筛选
        if let type = selectedType {
            result = result.filter { $0.type == type }
        }
        
        // 按搜索文本筛选
        if !searchText.isEmpty {
            result = result.filter { video in
                video.name.localizedCaseInsensitiveContains(searchText) ||
                (video.actors?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (video.director?.localizedCaseInsensitiveContains(searchText) ?? false)
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
                    TextField("搜索视频...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // 类型选择器
                if !types.isEmpty {
                    Menu {
                        Button("全部类型") {
                            selectedType = nil
                        }
                        Divider()
                        ForEach(types, id: \.self) { type in
                            Button(type) {
                                selectedType = type
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedType ?? "全部")
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
                
                // 刷新按钮
                Button {
                    reloadFromFirstPage()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(isLoading || isLoadingMore)
            }
            .padding()
            
            Divider()
            
            // 视频列表
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("加载视频列表...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("加载失败")
                        .font(.title3.bold())
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        loadVideos(page: 1)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if displayVideos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "film.stack" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "暂无视频" : "无匹配结果")
                        .font(.title3.bold())
                    if !searchText.isEmpty {
                        Button("清除搜索") {
                            searchText = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
                    ], spacing: 20) {
                        ForEach(displayVideos) { video in
                            Button {
                                selectedVideo = video
                                showingVideoDetail = true
                            } label: {
                                VideoCard(video: video)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                // 滚动到倒数第5个时触发加载更多
                                if video.id == displayVideos.dropLast(4).last?.id {
                                    loadMoreIfNeeded()
                                }
                            }
                        }
                        
                        // 加载更多指示器
                        if isLoadingMore {
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("加载更多...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .gridCellColumns(2)
                        } else if !hasMorePages && videos.count > 0 {
                            Text("已加载全部 \(videos.count) 个视频")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .gridCellColumns(2)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(source.name)
        .onAppear {
            if videos.isEmpty {
                loadVideos(page: 1)
            }
        }
        .sheet(isPresented: $showingVideoDetail) {
            if let video = selectedVideo {
                VODDetailView(video: video, source: source)
                    .environmentObject(appState)
            }
        }
    }
    
    // MARK: - 数据加载
    
    private func loadVideos(page: Int) {
        guard let db = appState.database else { return }
        
        if page == 1 {
            isLoading = true
            currentPage = 1
            hasMorePages = true
        }
        
        errorMessage = nil
        
        Task {
            do {
                let service = VODService(db: db)
                let loaded = try await service.fetchVideos(from: source, page: page)
                
                await MainActor.run {
                    if page == 1 {
                        self.videos = loaded
                    } else {
                        self.videos.append(contentsOf: loaded)
                    }
                    
                    self.currentPage = page
                    self.hasMorePages = loaded.count >= 100  // 如果返回满页，说明可能还有更多
                    self.isLoading = false
                    self.isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.isLoadingMore = false
                }
            }
        }
    }
    
    private func loadMoreIfNeeded() {
        guard !isLoadingMore && !isLoading && hasMorePages else { return }
        
        isLoadingMore = true
        loadVideos(page: currentPage + 1)
    }
    
    private func reloadFromFirstPage() {
        videos = []
        loadVideos(page: 1)
    }
}

// MARK: - 视频卡片视图

private struct VideoCard: View {
    let video: VODVideo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 海报
            AsyncImage(url: video.pic.flatMap { URL(string: $0) }) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            ProgressView()
                        }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // 标题
            Text(video.name)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // 元信息
            HStack(spacing: 4) {
                if let type = video.type {
                    Text(type)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let year = video.year {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(year)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 160)
    }
}
