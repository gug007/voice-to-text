import AppKit
import SwiftUI

// MARK: - Metrics
//
// The five magic `NSSize` constants that used to decide how big each panel was
// are gone. What is left is the vocabulary the card is built out of: one inset,
// one gap, one height per section. The card's size is the sum of whatever
// sections its mode shows, and the PANEL's size is the card plus a transparent
// shadow gutter. Change a section height here and every dependent size follows.

nonisolated enum HUDMetrics {
    /// Transparent border around the card, inside the panel. The card's drop
    /// shadow lives here, which is why the panel itself has `hasShadow = false`.
    /// Three 24pt blur radii plus the 16pt vertical offset avoids a hard edge.
    static let gutter: CGFloat = 88
    /// Card content inset — 12, down from 20. This is what fixed the compact
    /// recording overflow (112pt of content in an 88pt box).
    /// Every HUD control is therefore radius 22 − 12 = 10, concentrically.
    static let inset: CGFloat = Space.s5
    /// Gap between card sections.
    static let gap: CGFloat = Space.s5

    /// Compact card width: recording and transcribing.
    static let compactWidth: CGFloat = 420
    /// Wide card width: review, failure, and any session resumed out of review.
    static let wideWidth: CGFloat = 600

    static let meterHeight: CGFloat = 56
    /// The meter beside a resumed take's transcript.
    static let inlineMeterHeight: CGFloat = 26
    /// Exactly three reserved lines of streaming transcript.
    static let streamTextHeight: CGFloat = 60
    /// The resumed take's read-only transcript block.
    static let resumeTextHeight: CGFloat = 120
    static let editorHeight: CGFloat = 172
    static let chipRowHeight: CGFloat = 30
    static let bannerHeight: CGFloat = 34
    static let emptyStateHeight: CGFloat = 20
    /// Model name, phase line and progress bar, stacked.
    static let preparingHeight: CGFloat = 56
    /// Control row: one 28pt control, which is the macOS 26 regular metric.
    static let controlRowHeight: CGFloat = 28

    /// Minimum card heights — the spec's target sizes. Content never has to
    /// fill them; the compact layouts keep ~12pt of deliberate slack rather
    /// than hugging the meter.
    static let recordingMinHeight: CGFloat = 132
    static let recordingLiveMinHeight: CGFloat = 204
    static let reviewMinHeight: CGFloat = 236
    static let reviewChipsMinHeight: CGFloat = 278

    /// Default placement: panel bottom edge 56pt above the visible frame.
    static let defaultBottomInset: CGFloat = 56
    /// Never let the panel touch a screen edge.
    static let screenMargin: CGFloat = 8

    /// `Motion.hudMorph` is `.bouncy(duration: 0.38, extraBounce: 0.06)`. The
    /// NSPanel frame has to travel on the same clock, and AppKit only speaks
    /// `CAMediaTimingFunction`, so this cubic is hand-matched to that spring:
    /// same duration, ~6% overshoot from the control point above 1, settling
    /// flat. It is the closest a Bézier gets to a spring, and the reason the
    /// morph has a kill switch (`HUDFeatureFlags.morphKey`).
    static let morphDuration: TimeInterval = 0.38
    static var morphTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.32, 1.18, 0.52, 1)
    }
}

// MARK: - Layout

/// Which sections the card shows for the current state, and how big that makes
/// it. One value drives both the SwiftUI card and the panel-frame estimate, so
/// the two cannot disagree about what is on screen.
nonisolated struct HUDLayout: Equatable, Sendable {
    let mode: LiveHUDMode
    let showsLiveText: Bool
    let showsChips: Bool
    let hasBanner: Bool
    /// This session came out of a review (Resume), so it keeps the review width.
    let resumedSession: Bool

    @MainActor
    init(state: LiveHUDState) {
        mode = state.mode
        showsLiveText = state.showsLiveText
        showsChips = state.reviewShowsActions
        hasBanner = switch state.mode {
        case .reviewing, .resumeRecording: state.reviewBanner != nil
        case .failed: true
        case .preparing, .recording, .transcribing: false
        }
        resumedSession = state.resumedSession
    }

    // MARK: Sections

    /// A resumed take, from the moment Resume is pressed until review comes
    /// back: it records, then it transcribes. Both phases show the same three
    /// sections in the same slots, which is the whole point — the transcript
    /// never blanks, and the meter freezes exactly where it was live.
    ///
    /// Transcribing used to drop to the full-height meter and the control row
    /// alone, 120pt of content in the 278pt card resume holds for continuity.
    /// Nothing could absorb the other 158pt, so the two survivors floated in
    /// the middle of an otherwise empty card with the transcript nowhere in
    /// sight — even though `showTranscribing` never clears it.
    private var isResumedTake: Bool {
        mode == .resumeRecording || (mode == .transcribing && resumedSession)
    }

    /// The full-height meter. Present in recording AND transcribing — the bars
    /// freeze and desaturate in place instead of being replaced by dots. A
    /// resumed take freezes its inline meter instead, in the same slot.
    var showsMeter: Bool {
        switch mode {
        case .recording: return true
        case .transcribing: return !resumedSession
        case .preparing, .resumeRecording, .reviewing, .failed: return false
        }
    }

    /// Model name, phase line and progress bar, while the model is fetched or
    /// loaded. Absorbs the card's slack (see `preparingHeight`) so the control
    /// row still sits on the bottom edge exactly where recording puts it.
    var showsPreparing: Bool {
        mode == .preparing
    }

    var showsStreamText: Bool {
        mode == .recording && showsLiveText
    }

    var showsResumeTranscript: Bool {
        isResumedTake
    }

    /// The 26pt meter row (dot · meter · clock) under a resumed take.
    var showsInlineMeter: Bool {
        isResumedTake
    }

    var showsEditor: Bool {
        mode == .reviewing
    }

    var showsEmptyState: Bool {
        mode == .failed
    }

    var showsChipRow: Bool {
        mode == .reviewing && showsChips
    }

    // MARK: Size

    var isWide: Bool {
        switch mode {
        case .reviewing, .failed, .resumeRecording: return true
        // A resumed take's transcribing phase keeps the review width so the
        // morph never snaps back to compact mid-session.
        case .transcribing: return resumedSession
        // Preparing is compact because it only ever precedes a compact
        // recording card: a take resumed out of review keeps the review card on
        // screen instead of showing this one (see `beginPreparingPhase`).
        case .preparing, .recording: return false
        }
    }

    var width: CGFloat {
        isWide ? HUDMetrics.wideWidth : HUDMetrics.compactWidth
    }

    var minHeight: CGFloat {
        switch mode {
        // Same height as the recording card it hands over to, so the morph into
        // recording moves nothing but the content.
        case .preparing:
            return HUDMetrics.recordingMinHeight
        case .recording:
            return showsLiveText ? HUDMetrics.recordingLiveMinHeight : HUDMetrics.recordingMinHeight
        case .transcribing:
            if resumedSession { return reviewHeight }
            return showsLiveText ? HUDMetrics.recordingLiveMinHeight : HUDMetrics.recordingMinHeight
        // A resumed take keeps the review session's exact height so the
        // transcript underneath it does not shift by a pixel.
        case .resumeRecording, .reviewing, .failed:
            return reviewHeight
        }
    }

    private var reviewHeight: CGFloat {
        showsChips ? HUDMetrics.reviewChipsMinHeight : HUDMetrics.reviewMinHeight
    }

    /// The heights of the sections this mode stacks, top to bottom.
    private var sectionHeights: [CGFloat] {
        var rows = fixedSectionHeights
        if showsEmptyState { rows.insert(emptyStateHeight, at: rows.count - 1) }
        if showsPreparing { rows.insert(preparingHeight, at: rows.count - 1) }
        if showsResumeTranscript { rows.insert(resumeTranscriptHeight, at: hasBanner ? 1 : 0) }
        return rows
    }

    /// Every section whose height is a constant — that is, all of them except
    /// the one that absorbs the card's slack.
    private var fixedSectionHeights: [CGFloat] {
        var rows: [CGFloat] = []
        if hasBanner { rows.append(HUDMetrics.bannerHeight) }
        if showsMeter { rows.append(HUDMetrics.meterHeight) }
        if showsStreamText { rows.append(HUDMetrics.streamTextHeight) }
        if showsInlineMeter { rows.append(HUDMetrics.inlineMeterHeight) }
        if showsEditor { rows.append(HUDMetrics.editorHeight) }
        if showsChipRow { rows.append(HUDMetrics.chipRowHeight) }
        rows.append(HUDMetrics.controlRowHeight)
        return rows
    }

    /// What is left of `minHeight` for the one section that absorbs this card's
    /// slack, never less than its `natural` height.
    ///
    /// A card whose sections are shorter than its minimum height has to give
    /// that difference to SOMETHING. Left alone, `.frame(minHeight:)` centres
    /// the stack and hands half to the top inset and half to the bottom one,
    /// which lifts the control row off the card's bottom edge — the one thing
    /// that is identical in every mode.
    private func absorbedHeight(natural: CGFloat) -> CGFloat {
        let fixed = fixedSectionHeights
        let used = fixed.reduce(0, +)
            + HUDMetrics.gap * CGFloat(fixed.count)
            + HUDMetrics.inset * 2
        return max(natural, minHeight - used)
    }

    /// The failure card's content is far shorter than its minimum height, so
    /// the empty-state block takes the difference.
    var emptyStateHeight: CGFloat {
        absorbedHeight(natural: HUDMetrics.emptyStateHeight)
    }

    /// The preparing card's three lines are shorter than the recording height it
    /// holds, and the control row must stay welded to the bottom edge, so this
    /// block takes the difference — same rule as the empty state.
    var preparingHeight: CGFloat {
        absorbedHeight(natural: HUDMetrics.preparingHeight)
    }

    /// The resumed take's transcript takes the difference for the same reason,
    /// and it is the section that should: resume holds the REVIEW card's height
    /// so the transcript does not move when Resume is pressed, but it shows one
    /// section fewer than review did (no chip row, 42pt with its gap). Growing
    /// the transcript into exactly that space is what makes the promise true —
    /// centred slack put 28pt of dead air at each end and dropped the text 28pt
    /// the moment recording resumed.
    var resumeTranscriptHeight: CGFloat {
        absorbedHeight(natural: HUDMetrics.resumeTextHeight)
    }


    /// What the card will measure once SwiftUI lays it out.
    ///
    /// Exact for every fixed-height section, which is all of them — the panel
    /// can therefore start its frame animation in the same runloop turn as the
    /// card's spring instead of a frame later. `LiveHUDPanel.cardSizeChanged`
    /// corrects the rare case where content grew past the estimate (a failure
    /// message that wraps to two lines).
    var estimatedCardSize: CGSize {
        let rows = sectionHeights
        let content = rows.reduce(0, +)
            + HUDMetrics.gap * CGFloat(max(0, rows.count - 1))
            + HUDMetrics.inset * 2
        return CGSize(width: width, height: max(minHeight, content))
    }
}
