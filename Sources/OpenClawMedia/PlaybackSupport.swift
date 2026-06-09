import Foundation
import AVFoundation
import Combine

struct ResolvedPlaybackRoute: Equatable {
    let url: URL
    let label: String
    let route: IPTVRoute?
    let isNativePreferred: Bool
    let reason: String
}

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

@MainActor
final class NativePlaybackManager: ObservableObject {
    @Published var player = AVPlayer()
    @Published var nowPlayingTitle = ""
    @Published var nowPlayingURL: URL?
    @Published var playbackStatus = "Idle"
    @Published var isPlaying = false

    func play(url: URL, title: String) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        nowPlayingURL = url
        nowPlayingTitle = title
        playbackStatus = "Playing: \(title)"
        isPlaying = true
        player.play()
    }

    func pause() {
        player.pause()
        isPlaying = false
        playbackStatus = nowPlayingTitle.isEmpty ? "Paused" : "Paused: \(nowPlayingTitle)"
    }

    func resume() {
        player.play()
        isPlaying = true
        playbackStatus = nowPlayingTitle.isEmpty ? "Playing" : "Playing: \(nowPlayingTitle)"
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        nowPlayingURL = nil
        nowPlayingTitle = ""
        playbackStatus = "Stopped"
        isPlaying = false
    }
}
