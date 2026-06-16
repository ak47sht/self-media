import SwiftUI
import MediaLibCore

/// VOD 视频库视图
struct VODLibraryView: View {
    @EnvironmentObject private var appState: AppState
    let source: MediaSource
    
    @State private var videos: [VODVideo] = []
    @State private var filteredVideos: [VODVideo] = []
    @State private var searchText = ""
    @State private var selectedType: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
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
                        .foregroundStyle(.red)
                    Text("加载失败")
                        .font(.headline)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重新加载") {
                        loadVideos()
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
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
                    ], spacing: 16) {
                        ForEach(displayVideos) { video in
                            NavigationLink {
                                VODDetailView(video: video, source: source)
                            } label: {
                                VideoCard(video: video)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(source.name)
        .navigationSubtitle("\(displayVideos.count) 个视频")
        .onAppear {
            if videos.isEmpty {
                loadVideos()
            }
        }
    }
    
    private func loadVideos() {
        guard let db = appState.database else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let service = VODService(db: db)
                let loaded = try service.loadCachedVideos(sourceID: source.id)
                
                await MainActor.run {
                    self.videos = loaded
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
}

// MARK: - 视频卡片视图

private struct VideoCard: View {
    let video: VODVideo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                            Image(systemName: "film")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(height: 240)
                    .overlay {
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // 标题
            Text(video.name)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(.primary)
            
            // 元信息
            HStack(spacing: 4) {
                if let type = video.type {
                    Text(type)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let year = video.year {
                    if video.type != nil {
                        Text("·")
                            .foregroundStyle(.secondary)
                    }
                    Text(year)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Array Extension

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
