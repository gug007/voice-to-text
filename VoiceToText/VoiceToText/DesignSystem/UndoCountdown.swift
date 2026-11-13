import Observation
import SwiftUI

/// An Undo window that pauses while the pointer is on its notice. `onExpire`
/// fires when the ring empties and never sooner, however long the pauses were.
@MainActor
@Observable
final class UndoCountdown {
    private(set) var timeline: UndoCountdownTimeline
    @ObservationIgnored private var onExpire: (@MainActor () -> Void)?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    init(duration: TimeInterval, onExpire: @escaping @MainActor () -> Void) {
        timeline = UndoCountdownTimeline(duration: duration, startedAt: Self.now)
        self.onExpire = onExpire
        schedule()
    }

    var isPaused: Bool { timeline.isPaused }

    /// Hovering the notice pauses it; leaving resumes it, with the deadline
    /// pushed back by the time spent paused. A pause that outlasts
    /// `UndoCountdownTimeline.maxPause` resumes by itself.
    func setPaused(_ paused: Bool) {
        guard onExpire != nil, paused != timeline.isPaused else { return }
        if paused {
            timeline.pause(at: Self.now)
        } else {
            timeline.resume(at: Self.now)
        }
        schedule()
    }

    /// Closes the window without firing. Idempotent.
    func cancel() {
        expiry?.cancel()
        expiry = nil
        onExpire = nil
    }

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func schedule() {
        expiry?.cancel()
        expiry = nil
        guard onExpire != nil else { return }
        let paused = timeline.isPaused
        let wait = paused ? UndoCountdownTimeline.maxPause : timeline.remaining(at: Self.now)
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            if paused { self?.setPaused(false) } else { self?.fireIfDue() }
        }
    }

    private func fireIfDue() {
        guard timeline.isExpired(at: Self.now) else {
            schedule()
            return
        }
        let fire = onExpire
        onExpire = nil
        expiry = nil
        fire?()
    }
}

/// The ring inside an Undo button: full when the window opens, empty when it
/// lapses. Drains smoothly, holds still while paused, and under Reduce Motion
/// steps once a second instead. Drawn in the button's foreground, so it takes
/// the colour of the label beside it.
struct UndoCountdownRing: View {
    let countdown: UndoCountdown

    @Environment(\.motion) private var motion

    private static let diameter: CGFloat = 12
    private static let lineWidth: CGFloat = 1.75

    var body: some View {
        // The timeline only decides when to redraw; the time read is the
        // countdown's own clock, so the ring and the expiry share one.
        TimelineView(.animation(minimumInterval: motion.reduceMotion ? 0.25 : 1.0 / 30, paused: countdown.isPaused)) { _ in
            let now = UndoCountdown.now
            let timeline = countdown.timeline
            let fraction = motion.reduceMotion ? timeline.steppedFraction(at: now) : timeline.fraction(at: now)
            ZStack {
                Circle()
                    .stroke(lineWidth: Self.lineWidth)
                    .opacity(0.25)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: Self.diameter, height: Self.diameter)
        }
        .accessibilityHidden(true)
    }
}
