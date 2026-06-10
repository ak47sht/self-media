import Foundation
import AVFoundation
import Combine

// MARK: - Playback State

enum PlaybackState: Equatable {
    case idle
    case loading(String)      // e.g. "Buffering…"
    case playing(String)      // e.g. "Playing: CCTV-1"
    case paused(String)       // e.g. "Paused: CCTV-1"
    case stalled(String)      // e.g. "Stalled — buffering"
    case error(String)        // e.g. "Failed: connection lost"
    case completed

    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .loading(let msg): return msg
        case .playing(let msg): return msg
        case .paused(let msg): return msg
        case .stalled(let msg): return msg
        case .error(let msg): return msg
        case .completed: return "Playback finished"
        }
    }

    var isActive: Bool {
        switch self {
        case .playing, .loading, .stalled: return true
        default: return false
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - Resolved Route

struct ResolvedPlaybackRoute: Equatable {
    let url: URL
    let label: String
    let route: IPTVRoute?
    let isNativePreferred: Bool
    let reason: String
}

// MARK: - Route Resolver

enum PlaybackRouteResolver {
    static func resolve(channel: IPTVChannel, selectedRoute: IPTVRoute? = nil, allowHTTP: Bool = true) -> ResolvedPlaybackRoute? {
        let candidates = selectedRoute.map { [$0] } ?? channel.routes
        let sorted = candidates.sorted { lhs, rhs in
            score(lhs, allowHTTP: allowHTTP) > score(rhs, allowHTTP: allowHTTP)
        }
        if let route = sorted.compactMap({ route -> ResolvedPlaybackRoute? in
            guard let url = URL(string: route.playURL.isEmpty ? route.url : route.playURL) else { return nil }
            return ResolvedPlaybackRoute(
                url: url,
                label: route.label.isEmpty ? route.sourceName : route.label,
                route: route,
                isNativePreferred: isNativeURL(url) && (route.browserPlayable || url.pathExtension.lowercased() == "m3u8"),
                reason: route.browserPlayable ? "Native playable route" : "Best available stream URL"
            )
        }).first {
            return route
        }
        guard let fallback = URL(string: channel.playURL.isEmpty ? channel.url : channel.playURL) else { return nil }
        return ResolvedPlaybackRoute(
            url: fallback,
            label: channel.sourceName.isEmpty ? channel.name : channel.sourceName,
            route: nil,
            isNativePreferred: isNativeURL(fallback) && channel.browserPlayable,
            reason: channel.browserPlayable ? "Channel native URL" : "Channel fallback URL"
        )
    }

    /// Return all scored and sorted fallback routes for a channel, excluding the current route.
    static func fallbackRoutes(for channel: IPTVChannel, excluding currentRoute: IPTVRoute? = nil, allowHTTP: Bool = true) -> [ResolvedPlaybackRoute] {
        let candidates = channel.routes.filter { $0.id != currentRoute?.id }
        let sorted = candidates.sorted { lhs, rhs in
            score(lhs, allowHTTP: allowHTTP) > score(rhs, allowHTTP: allowHTTP)
        }
        return sorted.compactMap { route -> ResolvedPlaybackRoute? in
            guard let url = URL(string: route.playURL.isEmpty ? route.url : route.playURL) else { return nil }
            return ResolvedPlaybackRoute(
                url: url,
                label: route.label.isEmpty ? route.sourceName : route.label,
                route: route,
                isNativePreferred: isNativeURL(url) && (route.browserPlayable || url.pathExtension.lowercased() == "m3u8"),
                reason: route.browserPlayable ? "Fallback native route" : "Fallback stream URL"
            )
        }
    }

    private static func score(_ route: IPTVRoute, allowHTTP: Bool) -> Int {
        guard let url = URL(string: route.playURL.isEmpty ? route.url : route.playURL) else { return -100 }
        var value = 0
        if route.browserPlayable { value += 50 }
        if url.scheme?.lowercased() == "https" { value += 30 }
        if allowHTTP && url.scheme?.lowercased() == "http" { value += 12 }
        if url.pathExtension.lowercased() == "m3u8" { value += 25 }
        if route.label.lowercased().contains("高清") || route.label.lowercased().contains("hd") { value += 4 }
        return value
    }

    private static func isNativeURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }
}

// MARK: - Native Playback Manager

@MainActor
final class NativePlaybackManager: ObservableObject {
    @Published var player = AVPlayer()
    @Published var nowPlayingTitle = ""
    @Published var nowPlayingURL: URL?
    @Published var playbackStatus = "Idle"
    @Published var isPlaying = false
    @Published var state: PlaybackState = .idle
    @Published var fallbackRoutes: [ResolvedPlaybackRoute] = []
    @Published var currentRouteIndex: Int = 0
    @Published var autoFallbackEnabled = true

    /// Max auto-fallback attempts before giving up.
    var maxFallbackAttempts = 3

    private var fallbackAttempts = 0
    private var playerItemObserver: NSKeyValueObservation?
    private var timeControlKVO: NSKeyValueObservation?
    private var timeControlObserver: NSObjectProtocol?
    private var didEndObserver: NSObjectProtocol?
    private var errorObserver: NSObjectProtocol?

    // Callback to request route switch from parent view (IPTV channel context).
    var onRouteFallbackRequested: ((IPTVChannel) async -> Void)?

    func play(url: URL, title: String, fallbacks: [ResolvedPlaybackRoute] = []) {
        stopObserving()
        fallbackAttempts = 0
        fallbackRoutes = fallbacks
        currentRouteIndex = 0

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        nowPlayingURL = url
        nowPlayingTitle = title
        playbackStatus = "Loading: \(title)"
        isPlaying = true
        state = .loading("Buffering…")

        observe(item: item)
        player.play()
    }

    func play(url: URL, title: String) {
        play(url: url, title: title, fallbacks: [])
    }

    func pause() {
        player.pause()
        isPlaying = false
        state = .paused(nowPlayingTitle.isEmpty ? "Paused" : "Paused: \(nowPlayingTitle)")
        playbackStatus = state.displayText
    }

    func resume() {
        player.play()
        isPlaying = true
        state = .playing(nowPlayingTitle.isEmpty ? "Playing" : "Playing: \(nowPlayingTitle)")
        playbackStatus = state.displayText
    }

    func stop() {
        stopObserving()
        player.pause()
        player.replaceCurrentItem(with: nil)
        nowPlayingURL = nil
        nowPlayingTitle = ""
        playbackStatus = "Stopped"
        isPlaying = false
        state = .idle
        fallbackRoutes = []
        fallbackAttempts = 0
    }

    /// Attempt to play the next fallback route automatically.
    func tryNextFallback() -> Bool {
        guard fallbackAttempts < min(fallbackRoutes.count, maxFallbackAttempts) else {
            state = .error("All routes failed (\(fallbackAttempts) attempts). Try copying URL or opening in IINA.")
            playbackStatus = state.displayText
            isPlaying = false
            return false
        }

        let next = fallbackRoutes[fallbackAttempts]
        fallbackAttempts += 1
        currentRouteIndex = fallbackAttempts

        let item = AVPlayerItem(url: next.url)
        player.replaceCurrentItem(with: item)
        nowPlayingURL = next.url
        state = .loading("Trying route \(fallbackAttempts)/\(fallbackRoutes.count): \(next.label)")
        playbackStatus = state.displayText

        stopObserving()
        observe(item: item)
        player.play()
        return true
    }

    // MARK: - Observation

    private func observe(item: AVPlayerItem) {
        // Key-value observation for item status
        playerItemObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleItemStatus(item)
            }
        }

        // Notification-based observation for time control and errors
        timeControlObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped, object: item, queue: .main
        ) { [weak self] _ in
            self?.handleTimeControlChange()
        }

        // Observe playback stall
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.state = .stalled("Playback stalled — buffering")
                self?.playbackStatus = self?.state.displayText ?? "Stalled"
            }
        }

        // Observe when item ends
        didEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.state = .completed
                self?.playbackStatus = "Playback finished"
                self?.isPlaying = false
            }
        }

        // Observe errors
        errorObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                let reason = error?.localizedDescription ?? "Unknown playback error"
                self?.handlePlaybackError(reason: reason)
            }
        }

        // KVO on player's own timeControlStatus for play/pause/buffer changes
        timeControlKVO = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.handleTimeControlStatus(player.timeControlStatus)
            }
        }
    }

    private func stopObserving() {
        playerItemObserver?.invalidate()
        playerItemObserver = nil
        timeControlKVO?.invalidate()
        timeControlKVO = nil

        if let obs = timeControlObserver { NotificationCenter.default.removeObserver(obs) }
        timeControlObserver = nil
        if let obs = didEndObserver { NotificationCenter.default.removeObserver(obs) }
        didEndObserver = nil
        if let obs = errorObserver { NotificationCenter.default.removeObserver(obs) }
        errorObserver = nil
    }

    private func handleItemStatus(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            state = .playing("Playing: \(nowPlayingTitle)")
            playbackStatus = state.displayText
            fallbackAttempts = 0  // Reset on success
        case .failed:
            let reason = item.error?.localizedDescription ?? "Unknown error"
            handlePlaybackError(reason: "Item failed: \(reason)")
        case .unknown:
            state = .loading("Loading…")
            playbackStatus = state.displayText
        @unknown default:
            break
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            if !state.isError {
                state = .playing("Playing: \(nowPlayingTitle)")
                playbackStatus = state.displayText
                isPlaying = true
            }
        case .paused:
            if !state.isError {
                state = .paused("Paused: \(nowPlayingTitle)")
                playbackStatus = state.displayText
                isPlaying = false
            }
        case .waitingToPlayAtSpecifiedRate:
            state = .stalled("Buffering…")
            playbackStatus = state.displayText
        @unknown default:
            break
        }
    }

    private func handleTimeControlChange() {
        // Generic time control change — just refresh status
        if !state.isError && !state.isActive {
            state = .loading("Loading…")
            playbackStatus = state.displayText
        }
    }

    private func handlePlaybackError(reason: String) {
        if autoFallbackEnabled && fallbackRoutes.count > fallbackAttempts {
            state = .error("Failed: \(reason) — auto-switching route…")
            playbackStatus = state.displayText
            // Small delay so the user sees the error before auto-switch
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
                _ = tryNextFallback()
            }
        } else {
            state = .error("Playback failed: \(reason)")
            playbackStatus = state.displayText
            isPlaying = false
        }
    }
}
