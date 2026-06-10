import SwiftUI

/// Full VOD experience: search across TVBox sources, view details, select episodes, play.
struct VODView: View {
    @ObservedObject var api: MediaAPI
    @ObservedObject var playback: NativePlaybackManager
    @ObservedObject var store: LocalStore
    let sources: [VODSource]
    let xtreamSources: [MediaSourceConfig]
    let config: AppConfig

    @State private var query = ""
    @State private var results: [VODSearchItem] = []
    @State private var searchStatus = "Search VOD titles across connected sources"
    @State private var isSearching = false
    @State private var selectedItem: VODSearchItem?
    @State private var detailItem: VODDetailItem?
    @State private var detailStatus = ""
    @State private var isDetailLoading = false
    @State private var isDetailPresented = false
    @State private var activeSource: VODSource?
    @State private var selectedEpisode: VODEpisode?
    @State private var resolvedRequestsByEpisode: [String: [PlaybackRequest]] = [:]
    @State private var xtreamSourceByVODID: [String: MediaSourceConfig] = [:]

    private let searchableSources: [VODSource]

    init(api: MediaAPI, playback: NativePlaybackManager, store: LocalStore, sources: [VODSource], xtreamSources: [MediaSourceConfig] = [], config: AppConfig) {
        self.api = api
        self.playback = playback
        self.store = store
        self.sources = sources
        self.xtreamSources = xtreamSources
        self.config = config
        self.searchableSources = sources.filter { $0.searchable }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Left: search + results
            VStack(alignment: .leading, spacing: 14) {
                header
                searchBar
                if isSearching {
                    ProgressView("Searching…").padding(.vertical, 8)
                }
                resultsGrid
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))

            // Right: detail panel
            detailPanel
        }
        .sheet(isPresented: $isDetailPresented) {
            detailSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("VOD Search")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("\(searchableSources.count) searchable sources · TVBox and Xtream direct API")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Label("\(results.count) results", systemImage: "rectangle.grid.1x2")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.mutedText)
                TextField("Movie, series, anime…", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await search() } }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 999, style: .continuous).stroke(AppTheme.hairline))

            Button { Task { await search() } } label: {
                Image(systemName: "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.purple)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
        }
    }

    // MARK: - Results grid

    private var resultsGrid: some View {
        ScrollView {
            if results.isEmpty && !isSearching {
                emptyState
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(results) { item in
                        VODResultCard(item: item, activeSource: activeSource) {
                            Task { await loadDetail(for: item) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.tv")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.mutedText.opacity(0.5))
            Text("Search for a movie or series")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
            Text("VOD sources are parsed from your TVBox config. Results come directly from source APIs — no backend proxy needed.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: - Detail panel (inline right)

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Detail")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)

            if let detailItem {
                detailContent(for: detailItem)
            } else if let selectedItem {
                VStack(spacing: 12) {
                    VODPosterPlaceholder(title: selectedItem.vodName, remarks: selectedItem.vodRemarks)
                        .frame(height: 160)
                    Text(selectedItem.vodName)
                        .font(.system(size: 18, weight: .semibold))
                    Text(selectedItem.vodRemarks ?? "Loading detail…")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)
                    ProgressView()
                    Text(detailStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.mutedText)
                }
            } else {
                Text("Select a title to view details and episode list.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
                    .padding(.top, 8)
            }
            Spacer()
        }
        .padding(18)
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline))
    }

    private func detailContent(for item: VODDetailItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VODPosterPlaceholder(title: item.vodName, remarks: item.vodRemarks)
                    .frame(height: 160)

                Text(item.vodName)
                    .font(.system(size: 20, weight: .semibold))

                infoRow(item: item)

                if !item.vodContent.isEmptyOrNil {
                    Text(item.vodContent ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(6)
                }

                // Episodes grouped by flag
                let episodes = item.episodes
                if episodes.isEmpty {
                    Text("No episodes found from this source.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                        .padding(.top, 8)
                } else {
                    ForEach(Array(groupEpisodes(episodes).enumerated()), id: \.offset) { groupIndex, group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.key)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.primaryText)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                                ForEach(group.value) { ep in
                                    Button {
                                        selectedEpisode = ep
                                        Task { await playEpisode(ep, detail: item) }
                                    } label: {
                                        Text(ep.title)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .background(selectedEpisode?.id == ep.id ? AppTheme.purple.opacity(0.25) : AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(10)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                if let ep = selectedEpisode {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(AppTheme.green)
                        Text("Selected: \(ep.title)")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    .padding(.top, 6)
                }

                PlaybackActionRow(
                    primaryTitle: "Play video",
                    isPlaying: playback.isPlaying,
                    play: { Task { await replaySelected(detail: item) } },
                    pause: { playback.pause() },
                    resume: { playback.resume() },
                    stop: { playback.stop() },
                    copyURL: { copyVODURL(to: item) },
                    openInIINA: { openVODInIINA(to: item) }
                )

                if let ep = selectedEpisode {
                    Button {
                        enqueueSelectedEpisode(ep, detail: item)
                    } label: {
                        Label("Add episode to Queue", systemImage: "text.line.first.and.arrowtriangle.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(playback.nowPlayingURL == nil && resolvedRequestsByEpisode[ep.id]?.first == nil)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Detail sheet (for compact windows)

    private var detailSheet: some View {
        Group {
            if let detailItem {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VODPosterPlaceholder(title: detailItem.vodName, remarks: detailItem.vodRemarks)
                                .frame(height: 200)
                            Text(detailItem.vodName)
                                .font(.system(size: 24, weight: .semibold))
                            infoRow(item: detailItem)
                            if !detailItem.vodContent.isEmptyOrNil {
                                Text(detailItem.vodContent ?? "")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        .padding()
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isDetailPresented = false }
                        }
                    }
                }
                .frame(minWidth: 560, idealWidth: 700, minHeight: 500)
            } else {
                ProgressView("Loading detail…")
            }
        }
    }

    // MARK: - Helpers

    private func infoRow(item: VODDetailItem) -> some View {
        HStack(spacing: 6) {
            if let year = item.vodYear { BadgeTag(text: year) }
            if let area = item.vodArea { BadgeTag(text: area) }
            if let type = item.typeName { BadgeTag(text: type) }
            if let remarks = item.vodRemarks { BadgeTag(text: remarks) }
        }
        .padding(.bottom, 4)
    }

    private func groupEpisodes(_ episodes: [VODEpisode]) -> [(key: String, value: [VODEpisode])] {
        let grouped = Dictionary(grouping: episodes, by: { $0.flag })
        return grouped.map { ($0.key, $0.value) }.sorted { $0.key < $1.key }
    }

    // MARK: - Actions

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        searchStatus = "Searching…"
        results = []
        xtreamSourceByVODID = [:]
        var allResults: [VODSearchItem] = []
        var errors: [String] = []

        for source in searchableSources.filter({ $0.ext != "xtream" }).prefix(5) {
            do {
                let response = try await api.searchVOD(source: source, query: q)
                if let list = response.list {
                    allResults.append(contentsOf: list)
                    if allResults.count >= 40 { break }  // Enough results
                }
            } catch {
                errors.append("\(source.name): \(error.localizedDescription)")
            }
        }

        for source in xtreamSources {
            do {
                let client = XtreamCodesClient(config: source)
                let categories = try await client.vodCategories()
                let streams = try await client.vodStreams()
                let items = XtreamCodesAdapter.searchItems(from: streams, categories: categories, query: q)
                for item in items { xtreamSourceByVODID[item.vodID] = source }
                allResults.append(contentsOf: items)
                if allResults.count >= 60 { break }
            } catch {
                errors.append("\(source.name): \(error.localizedDescription)")
            }
        }

        results = allResults
        activeSource = searchableSources.first
        isSearching = false
        searchStatus = allResults.isEmpty
            ? "No results found. Errors: \(errors.joined(separator: "; "))"
            : "Found \(allResults.count) titles across \(searchableSources.count) sources"
    }

    private func loadDetail(for item: VODSearchItem) async {
        selectedItem = item
        detailItem = nil
        selectedEpisode = nil
        resolvedRequestsByEpisode = [:]
        isDetailLoading = true
        detailStatus = "Loading detail…"

        if let xtreamSource = xtreamSourceByVODID[item.vodID] {
            do {
                let client = XtreamCodesClient(config: xtreamSource)
                let info = try await client.vodInfo(streamID: XtreamCodesAdapter.numericID(from: item.vodID))
                detailItem = try XtreamCodesAdapter.detailItem(from: info, fallback: item, source: xtreamSource)
                activeSource = searchableSources.first { $0.id == xtreamSource.id }
                detailStatus = "1 playable item · \(xtreamSource.name)"
            } catch {
                detailStatus = "Xtream detail failed: \(error.localizedDescription)"
            }
            isDetailLoading = false
            return
        }

        // Try sources in order until one returns valid detail with episodes
        for source in searchableSources.filter({ $0.ext != "xtream" }) {
            do {
                let resp = try await api.vodDetail(source: source, id: item.vodID)
                if let detail = resp.list?.first, !detail.episodes.isEmpty {
                    detailItem = detail
                    activeSource = source
                    detailStatus = "\(detail.episodes.count) episodes · \(source.name)"
                    isDetailLoading = false
                    return
                } else if let detail = resp.list?.first {
                    // Detail loaded but no episodes; keep trying other sources
                    if detailItem == nil { detailItem = detail }
                }
            } catch {
                continue
            }
        }

        isDetailLoading = false
        if detailItem == nil {
            detailStatus = "Could not load detail from any source. Try another title."
        } else if detailItem?.episodes.isEmpty == true {
            detailStatus = "Detail loaded but no playable episodes found."
        }
    }

    private func playEpisode(_ ep: VODEpisode, detail: VODDetailItem) async {
        guard let source = activeSource else { return }
        detailStatus = "Resolving stream URL…"

        do {
            let playResp: VODPlayResponse
            if source.ext == "xtream" {
                playResp = XtreamCodesAdapter.directPlayResponse(for: ep)
            } else {
                playResp = try await api.vodPlay(source: source, flag: ep.flag, id: ep.url)
            }
            let candidates = VODPlaybackResolver.resolve(response: playResp, source: source, episode: ep)
            resolvedRequestsByEpisode[ep.id] = candidates
            if let primary = candidates.first {
                playback.play(request: primary, title: "\(detail.vodName) · \(ep.title)", fallbacks: Array(candidates.dropFirst()))
                store.addToHistory(id: "\(detail.vodID)-\(ep.id)", type: .vodItem, title: detail.vodName, subtitle: ep.title, thumbnailURL: detail.vodPic, detailPath: ep.url)
                let headerNote = primary.headers.isEmpty ? "" : " · headers: \(primary.headers.keys.sorted().joined(separator: ", "))"
                detailStatus = "Playing: \(ep.title) · \(primary.reason)\(headerNote)"
            } else {
                detailStatus = VODPlaybackResolver.userMessage(for: playResp, candidates: candidates)
            }
        } catch {
            detailStatus = SourceDiagnostics.playbackFailure(kind: .vodTVBox, error: error)
        }
    }

    private func replaySelected(detail: VODDetailItem) async {
        if let ep = selectedEpisode {
            await playEpisode(ep, detail: detail)
        } else {
            detailStatus = "Select an episode first."
        }
    }

    private func copyVODURL(to detail: VODDetailItem) {
        guard let url = playback.nowPlayingURL else {
            detailStatus = "Nothing playing. Select and play an episode first."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        detailStatus = "Stream URL copied."
    }

    private func enqueueSelectedEpisode(_ ep: VODEpisode, detail: VODDetailItem) {
        let request = resolvedRequestsByEpisode[ep.id]?.first
        let streamURL = request.map(StreamURLNormalizer.serialize) ?? playback.nowPlayingURL?.absoluteString
        guard let streamURL else {
            detailStatus = "Resolve or play this episode before adding it to Queue."
            return
        }
        store.enqueue(
            id: "\(detail.vodID)-\(ep.id)-\(Date().timeIntervalSince1970)",
            type: .vodItem,
            title: detail.vodName,
            subtitle: ep.title,
            thumbnailURL: detail.vodPic,
            detailPath: ep.url,
            streamURL: streamURL
        )
        detailStatus = "Added to Queue: \(ep.title)"
    }

    private func openVODInIINA(to detail: VODDetailItem) {
        guard let url = playback.nowPlayingURL else {
            detailStatus = "Nothing playing. Select and play an episode first."
            return
        }
        let iinaURL = URL(string: "iina://weblink?url=\(url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString)")!
        if NSWorkspace.shared.open(iinaURL) {
            detailStatus = "Sent to IINA."
        } else {
            NSWorkspace.shared.open(url)
            detailStatus = "IINA not found; opened with system default."
        }
    }
}

// MARK: - VOD Subviews

struct VODResultCard: View {
    let item: VODSearchItem
    let activeSource: VODSource?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                VODPosterPlaceholder(title: item.vodName, remarks: item.vodRemarks)
                    .frame(height: 130)
                Text(item.vodName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                if let remarks = item.vodRemarks {
                    Text(remarks)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.hairline))
        }
        .buttonStyle(.plain)
    }
}

struct VODPosterPlaceholder: View {
    let title: String
    let remarks: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.purple.opacity(0.7), AppTheme.blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 6) {
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                if let remarks {
                    Text(remarks)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }
}

struct BadgeTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppTheme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.hairline))
    }
}

extension Optional where Wrapped == String {
    var isEmptyOrNil: Bool {
        self?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}
