import Foundation

/// Whether the input has clipped long enough to say so on the card, with
/// hysteresis so the caption doesn't flicker with every loud syllable.
nonisolated struct ClippingDetector: Sendable {
    /// Clipping time within `window` that turns the warning on.
    static let onAfter: TimeInterval = 1.0
    /// How far back clipping is added up.
    static let window: TimeInterval = 1.5
    /// Clip-free time that turns the warning off again.
    static let offAfter: TimeInterval = 2.0
    /// Longer than this between two samples is a gap in the feed, not
    /// clipping time: a stall must not count as a second of clipping.
    static let maxSampleGap: TimeInterval = 0.25

    private(set) var isSustained = false
    /// Spans of clipping inside the window, oldest first.
    private var spans: [ClosedRange<TimeInterval>] = []
    private var lastSample: (time: TimeInterval, clipping: Bool)?
    private var lastClipTime: TimeInterval?

    /// Feeds one sample. Returns whether the warning is on afterwards.
    @discardableResult
    mutating func update(isClipping: Bool, at time: TimeInterval) -> Bool {
        if let last = lastSample, last.clipping, time > last.time {
            let end = min(time, last.time + Self.maxSampleGap)
            append(last.time...end)
        }
        lastSample = (time, isClipping)
        if isClipping { lastClipTime = time }
        spans.removeAll { $0.upperBound < time - Self.window }

        if isSustained {
            if let lastClipTime, time - lastClipTime >= Self.offAfter {
                isSustained = false
                spans.removeAll()
            }
        } else if clippedSeconds(before: time) >= Self.onAfter {
            isSustained = true
        }
        return isSustained
    }

    mutating func reset() {
        self = ClippingDetector()
    }

    private mutating func append(_ span: ClosedRange<TimeInterval>) {
        if let last = spans.last, last.upperBound >= span.lowerBound {
            spans[spans.count - 1] = last.lowerBound...max(last.upperBound, span.upperBound)
        } else {
            spans.append(span)
        }
    }

    private func clippedSeconds(before time: TimeInterval) -> TimeInterval {
        let start = time - Self.window
        return spans.reduce(0) { total, span in
            total + max(0, span.upperBound - max(span.lowerBound, start))
        }
    }
}
