import SwiftUI
import MediaLibCore

/// VOD 视频库视图（支持分页加载）
struct VODLibraryView: View {
    @EnvironmentObject private var appState: AppState
    let source: MediaSource
    
    @State private var videos: [VODVideo] = []
    @State private var filteredVideos: [VODVideo] = []  // 搜索筛选后的结果
    @State private var searchText = ""
    @State private var selectedTypeID: Int?  // 选中的分类ID
    @State private var categories: [VODCategory] = []  // 完整分类列表
    @State private var isLoading = true
    @State private var isRefreshingCategories = false  // 刷新分类中
    @State private var errorMessage: String?
    
    // 分页状态
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    
    @State private var selectedVideo: VODVideo?
    @State private var loadingTask: Task<Void, Never>?
    @State private var categoryTask: Task<Void, Never>?
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var tvboxSites: [TVBoxVODSite] = []
    @State private var selectedTVBoxSiteID: String?
    @State private var isLoadingTVBoxSites = false
    @State private var tvboxSiteError: String?
    @State private var loadTVBoxTask: Task<Void, Never>?
    
    // displayVideos 计算属性在 sheet 弹出时会触发布局死循环，暂时禁用本地搜索
    // private var displayVideos: [VODVideo] {
    //     var result = videos
    //     
    //     // 按搜索文本筛选（本地筛选）
    //     if !searchText.isEmpty {
    //         result = result.filter { video in
    //             video.name.localizedCaseInsensitiveContains(searchText) ||
    //             (video.actors?.localizedCaseInsensitiveContains(searchText) ?? false) ||
    //             (video.director?.localizedCaseInsensitiveContains(searchText) ?? false)
    //         }
    //     }
    //     
    //     return result
    // }
    
    var body: some View {
        // 预计算分类相关数据，避免 body 内重复计算触发布局死循环
        let topCategories = effectiveTopCategories
        let selectedCategoryName: String = {
            guard let id = selectedTypeID,
                  let category = categories.first(where: { $0.id == id }) else {
                return "全部"
            }
            return category.name
        }()
        
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack(spacing: 12) {
                // 搜索框
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索视频...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // 刷新分类按钮
                Button {
                    Task {
                        await refreshCategories()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshingCategories ? 360 : 0))
                        .animation(isRefreshingCategories ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshingCategories)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingCategories)
                .help("刷新分类列表")
                
                // TVBox 站点选择器
                if isTVBoxAggregateSource {
                    if isLoadingTVBoxSites {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if !tvboxSites.isEmpty {
                        Menu {
                            ForEach(tvboxSites) { site in
                                Button(site.name) {
                                    switchTVBoxSite(site)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedTVBoxSite?.name ?? "选择站点")
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

                // 类型选择器
                if !categories.isEmpty {
                    Menu {
                        Button("全部类型") {
                            selectedTypeID = nil
                        }
                        Divider()
                        // 只显示顶级分类（type_pid == 0）及其子分类
                        ForEach(topCategories, id: \.id) { parent in
                            let children = categories.filter { $0.parentID == parent.id }
                            if children.isEmpty {
                                Button(parent.name) {
                                    selectedTypeID = parent.id
                                }
                            } else {
                                Menu(parent.name) {
                                    Button("全部\(parent.name)") {
                                        selectedTypeID = parent.id
                                    }
                                    Divider()
                                    ForEach(children, id: \.id) { child in
                                        Button(child.name) {
                                            selectedTypeID = child.id
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedCategoryName)
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
            } else if filteredVideos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "film.stack" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "暂无视频" : "无匹配结果")
                        .font(.title3.bold())
                    if !searchText.isEmpty {
                        Text("搜索 \"\(searchText)\" 未找到相关视频")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
                    ], spacing: 20) {
                        ForEach(filteredVideos) { video in
                            Button {
                                DebugLog.log("VODLibraryView", "🎯 点击视频封面: \(video.name)")
                                selectedVideo = video
                            } label: {
                                VideoCard(video: video)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                // 滚动到倒数第5个时触发加载更多
                                // 注意：这里用 filteredVideos 判断，但实际加载的是 videos
                                // 搜索时也允许服务端分页加载更多
                                if let idx = filteredVideos.firstIndex(where: { $0.id == video.id }),
                                   idx >= filteredVideos.count - 5 {
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
        .sheet(item: $selectedVideo) { video in
            VODDetailView(video: video, source: activeSource)
                .environmentObject(appState)
        }
        .navigationTitle(source.name)
        .onAppear {
            if isTVBoxAggregateSource {
                // Restore source-specific persisted site selection
                if let savedID = UserDefaults.standard.string(forKey: "vodlib_selected_tvbox_site_\(source.id)") {
                    selectedTVBoxSiteID = savedID
                }
                loadTVBoxSitesIfNeeded()
            } else {
                if categories.isEmpty {
                    loadCategories()
                }
                if videos.isEmpty {
                    loadVideos(page: 1)
                } else if filteredVideos.isEmpty {
                    // 如果 videos 有数据但 filteredVideos 为空（比如从其他页面返回），重新筛选
                    filterVideos()
                }
            }
        }
        .onChange(of: selectedTypeID) { newValue in
            // 类型切换时重新从 API 加载第一页
            DebugLog.log("VODLibraryView", "类型切换为: \(newValue.map(String.init) ?? "全部")")
            videos = []
            filteredVideos = []
            currentPage = 1
            hasMorePages = true
            loadVideos(page: 1)
        }
        .onChange(of: searchText) { _ in
            // 在线 VOD 搜索走服务端 wd=，不要只过滤当前已加载页。
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    reloadFromFirstPage()
                }
            }
        }
        .onChange(of: selectedTVBoxSiteID) { newValue in
            let key = "vodlib_selected_tvbox_site_\(source.id)"
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    
    // MARK: - 搜索筛选

    private var isTVBoxAggregateSource: Bool {
        source.onlineConfig?.kind == .vodTVBoxAggregate
    }

    private var selectedTVBoxSite: TVBoxVODSite? {
        guard isTVBoxAggregateSource else { return nil }
        if let selectedTVBoxSiteID,
           let site = tvboxSites.first(where: { $0.id == selectedTVBoxSiteID }) {
            return site
        }
        return tvboxSites.first
    }

    private var activeSource: MediaSource {
        guard let site = selectedTVBoxSite else { return source }
        let config = OnlineSourceConfig(
            kind: .vodTVBox,
            provider: "tvbox-cms",
            apiBase: site.api,
            subscriptionURL: source.onlineConfig?.subscriptionURL,
            epgURL: nil,
            userAgent: nil,
            quality: nil,
            needsParser: false
        )
        return MediaSource(
            id: "\(source.id)-\(site.id)",
            name: site.name,
            path: "vod://\(source.id)/\(site.id)",
            mediaType: .other,
            minimumFileSize: 0,
            includeInMetadataFetch: false,
            includeInHealthCheck: false,
            onlineConfig: config
        )
    }

    private var effectiveTopCategories: [VODCategory] {
        let declaredTop = categories.filter { $0.parentID == 0 }
        if !declaredTop.isEmpty { return declaredTop }
        let knownIDs = Set(categories.map(\.id))
        return categories.filter { !knownIDs.contains($0.parentID) }
    }
    
    private func filterVideos() {
        // 结果已由 VOD API 根据 wd= 返回；这里保持分页/搜索结果原样，避免“只能搜当前页”。
        filteredVideos = videos
    }
    
    // MARK: - 数据加载

    private func resetLoadedContent() {
        categories = []
        videos = []
        filteredVideos = []
        selectedTypeID = nil
        currentPage = 1
        hasMorePages = true
        errorMessage = nil
    }

    private func switchTVBoxSite(_ site: TVBoxVODSite) {
        guard selectedTVBoxSiteID != site.id else { return }
        DebugLog.log("VODLibraryView", "TVBox 切换站点: \(site.name)")
        selectedTVBoxSiteID = site.id
        resetLoadedContent()
        loadCategories()
        loadVideos(page: 1)
    }

    private func loadTVBoxSitesIfNeeded() {
        guard isTVBoxAggregateSource,
              tvboxSites.isEmpty,
              !isLoadingTVBoxSites else { return }
        guard let subscriptionURL = source.onlineConfig?.subscriptionURL,
              !subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            tvboxSiteError = "TVBox 聚合源缺少订阅地址。"
            errorMessage = tvboxSiteError
            isLoading = false
            return
        }
        isLoadingTVBoxSites = true
        isLoading = true
        loadTVBoxTask?.cancel()
        loadTVBoxTask = Task {
            do {
                let preview = try await TVBoxSubscriptionService().fetchPreview(from: subscriptionURL)
                try Task.checkCancellation()
                await MainActor.run {
                    self.tvboxSites = preview.vodSites
                    // Respect persisted site selection if still valid
                    if let persistedID = self.selectedTVBoxSiteID,
                       preview.vodSites.contains(where: { $0.id == persistedID }) {
                        // Keep persisted selection
                    } else {
                        self.selectedTVBoxSiteID = preview.vodSites.first?.id
                    }
                    self.isLoadingTVBoxSites = false
                    self.tvboxSiteError = preview.vodSites.isEmpty ? "TVBox 订阅里没有可直接播放的 CMS 点播站点。" : nil
                    if preview.vodSites.isEmpty {
                        self.isLoading = false
                        self.errorMessage = self.tvboxSiteError
                    } else {
                        self.resetLoadedContent()
                        self.loadCategories()
                        self.loadVideos(page: 1)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.isLoadingTVBoxSites = false
                    self.isLoading = false
                    self.tvboxSiteError = error.localizedDescription
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func refreshCategories() async {
        guard !isTVBoxAggregateSource || selectedTVBoxSite != nil else { return }
        guard let db = appState.database else { return }
        
        await MainActor.run {
            isRefreshingCategories = true
        }
        
        let requestedSource = activeSource
        do {
            let service = VODService(db: db)
            let loaded = try await service.fetchCategories(from: requestedSource)
            
            await MainActor.run {
                self.categories = loaded
                self.isRefreshingCategories = false
                DebugLog.log("VODLibraryView", "刷新分类成功: \(loaded.count) 个")
            }
        } catch {
            await MainActor.run {
                self.isRefreshingCategories = false
            }
            DebugLog.log("VODLibraryView", "❌ 刷新分类失败: \(error.localizedDescription)")
        }
    }
    
    private func loadCategories() {
        guard !isTVBoxAggregateSource || selectedTVBoxSite != nil else { return }
        guard let db = appState.database else { return }
        
        categoryTask?.cancel()
        let requestedSource = activeSource
        categoryTask = Task {
            do {
                let service = VODService(db: db)
                let loaded = try await service.fetchCategories(from: requestedSource)
                try Task.checkCancellation()
                
                await MainActor.run {
                    self.categories = loaded
                    DebugLog.log("VODLibraryView", "加载了 \(loaded.count) 个分类")
                }
            } catch is CancellationError {
                return
            } catch {
                DebugLog.log("VODLibraryView", "❌ 分类加载失败: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadVideos(page: Int) {
        guard !isTVBoxAggregateSource || selectedTVBoxSite != nil else { return }
        guard let db = appState.database else { return }
        
        if page == 1 {
            isLoading = true
            currentPage = 1
            hasMorePages = true
            DebugLog.log("VODLibraryView", "加载第一页，源: \(source.name)")
        } else {
            DebugLog.log("VODLibraryView", "加载第 \(page) 页")
        }
        
        if let typeID = selectedTypeID {
            DebugLog.log("VODLibraryView", "  筛选类型ID: \(typeID)")
        }
        
        errorMessage = nil
        
        if page == 1 {
            loadingTask?.cancel()
        }
        let requestedTypeID = selectedTypeID
        let requestedKeyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedSource = activeSource
        loadingTask = Task {
            do {
                let service = VODService(db: db)
                let result = try await service.fetchVideos(
                    from: requestedSource,
                    page: page,
                    keyword: requestedKeyword.isEmpty ? nil : requestedKeyword,
                    typeID: requestedTypeID.map(String.init)
                )
                try Task.checkCancellation()
                
                DebugLog.log("VODLibraryView", "API 返回 \(result.videos.count) 个视频，第 \(result.page)/\(result.pageCount) 页")
                
                await MainActor.run {
                    if page == 1 {
                        self.videos = result.videos
                        DebugLog.log("VODLibraryView", "  替换为新数据，总数: \(self.videos.count)")
                    } else {
                        self.videos.append(contentsOf: result.videos)
                        DebugLog.log("VODLibraryView", "  追加数据，总数: \(self.videos.count)")
                    }
                    
                    self.currentPage = result.page
                    self.hasMorePages = result.hasMore
                    self.isLoading = false
                    self.isLoadingMore = false
                    
                    // 数据加载完成后更新筛选结果
                    self.filterVideos()
                    
                    DebugLog.log("VODLibraryView", "  当前页: \(result.page), 还有更多: \(self.hasMorePages)")
                }
            } catch is CancellationError {
                return
            } catch {
                DebugLog.log("VODLibraryView", "❌ 加载失败: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.isLoadingMore = false
                }
            }
        }
    }
    
    private func loadMoreIfNeeded() {
        guard !isLoadingMore && !isLoading && hasMorePages else {
            if !hasMorePages {
                DebugLog.log("VODLibraryView", "已到最后一页，不再加载")
            }
            return
        }
        
        DebugLog.log("VODLibraryView", "触发加载更多（第 \(currentPage + 1) 页）")
        isLoadingMore = true
        loadVideos(page: currentPage + 1)
    }
    
    private func reloadFromFirstPage() {
        DebugLog.log("VODLibraryView", "刷新：重新加载第一页")
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
