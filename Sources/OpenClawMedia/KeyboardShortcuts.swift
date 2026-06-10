import SwiftUI
import AVFoundation

// MARK: - Keyboard shortcuts

func establishMediaKeyboardShortcuts(_ playback: NativePlaybackManager) -> NSObjectProtocol? {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { (event: NSEvent) -> NSEvent? in
        guard let window = NSApp.keyWindow,
              !(window.firstResponder is NSTextView),
              !(window.firstResponder is NSTextField) else { return event }
        let key = event.charactersIgnoringModifiers ?? ""
        switch key {
        case " ":
            playback.isPlaying ? playback.pause() : playback.resume()
            return nil
        case "k", "K":
            playback.stop()
            return nil
        case "f", "F":
            NSApp.keyWindow?.toggleFullScreen(nil)
            return nil
        case "m", "M":
            playback.player.isMuted.toggle()
            return nil
        default:
            return event
        }
    }
}

// MARK: - Playback control bar (progress + time + volume)

struct PlaybackControlBar: View {
    @ObservedObject var playback: NativePlaybackManager
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var volume: Float = 0.5

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 6) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.hairline)
                        .frame(height: 4)
                    if duration > 0 {
                        Capsule()
                            .fill(AppTheme.blue)
                            .frame(width: geo.size.width * (currentTime / duration), height: 4)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            guard duration > 0 else { return }
                            let ratio = val.location.x / geo.size.width
                            seek(to: ratio * duration)
                        }
                        .onEnded { val in
                            guard duration > 0 else { return }
                            let ratio = val.location.x / geo.size.width
                            seek(to: ratio * duration)
                        }
                )
            }
            .frame(height: 4)

            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.mutedText)
                Spacer()
                Text(formatTime(duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.mutedText)
            }

            // Volume slider
            HStack(spacing: 6) {
                Image(systemName: volume == 0 ? "speaker.slash.fill" : volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 18)
                Slider(value: Binding(
                    get: { Double(volume) },
                    set: { volume = Float($0); playback.player.volume = volume }
                ), in: 0...1)
                .tint(AppTheme.purple)
            }
        }
        .padding(12)
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.hairline))
        .onReceive(timer) { _ in
            updateTime()
        }
        .onAppear {
            volume = playback.player.volume
            updateTime()
        }
    }

    private func updateTime() {
        let player = playback.player
        currentTime = CMTimeGetSeconds(player.currentTime())
        if let d = player.currentItem?.duration, d.isNumeric {
            duration = CMTimeGetSeconds(d)
        }
    }

    private func seek(to seconds: Double) {
        let player = playback.player
        guard let d = player.currentItem?.duration, d.isNumeric else { return }
        let target = min(CMTimeGetSeconds(d), max(0, seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "--:--" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
