import Foundation

/// The clock behind a pausable Undo window, in `systemUptime` seconds; a pause
/// pushes the deadline back by as long as it lasted, up to `maxPause`.
nonisolated struct UndoCountdownTimeline: Equatable, Sendable {
    let duration: TimeInterval
    private(set) var deadline: TimeInterval
    private(set) var pausedAt: TimeInterval?

    init(duration: TimeInterval, startedAt start: TimeInterval) {
        self.duration = max(0, duration)
        deadline = start + self.duration
    }

    var isPaused: Bool { pausedAt != nil }

    func remaining(at now: TimeInterval) -> TimeInterval {
        max(0, min(duration, deadline - (pausedAt ?? now)))
    }

    func isExpired(at now: TimeInterval) -> Bool {
        !isPaused && remaining(at: now) <= 0
    }

    /// 1 when the window opens, 0 when it lapses.
    func fraction(at now: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return remaining(at: now) / duration
    }

    /// The same, in whole seconds left — for Reduce Motion, where the ring
    /// steps once a second instead of draining smoothly.
    func steppedFraction(at now: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, remaining(at: now).rounded(.up) / duration.rounded(.up))
    }

    mutating func pause(at now: TimeInterval) {
        guard pausedAt == nil else { return }
        pausedAt = min(now, deadline)
    }

    /// The longest one pause holds the window. A notice taken away under the
    /// pointer never hears it leave, so `UndoCountdown` resumes by itself
    /// once a pause has lasted this long.
    static let maxPause: TimeInterval = 30

    mutating func resume(at now: TimeInterval) {
        guard let pausedAt else { return }
        deadline += min(Self.maxPause, max(0, now - pausedAt))
        self.pausedAt = nil
    }
}
