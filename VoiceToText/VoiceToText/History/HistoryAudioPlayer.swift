import AVFoundation
import Observation
import OSLog

/// Plays back a saved recording for the History pane. Tracks which entry is
/// playing so a single row can render a play/stop toggle, and resets itself
/// when playback ends. One shared instance: starting a new clip stops any
/// currently-playing one.
@Observable
@MainActor
final class HistoryAudioPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = HistoryAudioPlayer()

    /// The entry currently playing, or nil when stopped. Drives the row icon.
    private(set) var playingID: UUID?

    @ObservationIgnored
    private var player: AVAudioPlayer?

    private override init() { super.init() }

    /// Plays `url` for `id`, or stops if that same entry is already playing.
    func toggle(url: URL, id: UUID) {
        if playingID == id {
            stop()
        } else {
            play(url: url, id: id)
        }
    }

    private func play(url: URL, id: UUID) {
        stop()
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else {
            AppLog.audio.error("History playback failed to open \(url.lastPathComponent, privacy: .public)")
            return
        }
        newPlayer.delegate = self
        player = newPlayer
        playingID = id
        newPlayer.play()
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    /// AVAudioPlayer dispatches this on the thread playback was started on —
    /// the main thread here — but the delegate requirement is nonisolated, so
    /// hop explicitly to satisfy isolation and clear the playing state. Carry a
    /// Sendable `ObjectIdentifier` rather than the non-Sendable `AVAudioPlayer`
    /// across the hop (identity comparison is preserved; Swift 6 clean).
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player,
                  ObjectIdentifier(current) == finished else { return }
            self.stop()
        }
    }
}
