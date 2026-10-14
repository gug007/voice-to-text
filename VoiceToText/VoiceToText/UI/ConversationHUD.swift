import AppKit
import Observation
import OSLog
import SwiftUI

// MARK: - Setting

/// Settings → Conversations → Recording HUD. A floating card for a conversation
/// that is recording or transcribing, at one of the dictation card's three
/// sizes, or none at all. Unlike dictation's size it applies at once, mid-
/// recording included — conversations run for an hour, and nobody should have
/// to stop one to get a smaller card.
nonisolated enum ConversationHUDSetting: String, CaseIterable, Identifiable, Sendable {
    case off, small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// The card's size, or nil for no card.
    var size: HUDSize? {
        switch self {
        case .off: return nil
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        }
    }

    static let defaultsKey = "conversation.hud"
    /// What `current` and the Settings picker fall back to when nothing is
    /// stored. One value, so the two cannot disagree about a fresh install.
    static let defaultValue: ConversationHUDSetting = .small

    static var current: ConversationHUDSetting {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? defaultValue
    }
}

// MARK: - State

/// What the conversation card draws, mirrored from `MeetingController` by the
/// panel rather than read off it directly. The mirror is what lets the card
/// hold its last frame while it fades out — the controller is already idle by
/// then, and has zeroed its clock and meter.
@Observable
@MainActor
final class ConversationHUDState {
    var size: HUDSize = .small
    var isTranscribing = false
    var elapsed: TimeInterval = 0
    /// The meter. Copied only while recording: the controller zeroes its
    /// history the moment Stop is pressed, a beat before it leaves
    /// `.recording`, so this copy is what freezes the bars where they stopped
    /// instead of flattening them.
    var levels: [Double] = Array(repeating: 0, count: MeetingController.levelHistoryCount)
    var transcribedChunks = 0
    var totalChunks = 0

    /// Bumped each time the card appears from hidden, which replays its
    /// entrance (see `HUDPresentation`).
    var presentationCount = 0
    /// Set inside `hudExit` while the card leaves; the panel orders out when
    /// that animation finishes.
    var isDismissing = false
    /// When the card appeared or last changed size, on the monotonic clock.
    /// A Stop button that moves or pops up under the pointer must not take a
    /// click aimed at whatever was there before — see `LiveHUDState.click`.
    @ObservationIgnored var placedAt: TimeInterval = 0

    /// "3/12" while a long recording transcribes in chunks; nil for one chunk,
    /// where a counter would only ever say "0/1".
    var chunkProgress: String? {
        totalChunks > 1 ? "\(transcribedChunks)/\(totalChunks)" : nil
    }
}

// MARK: - Panel

/// Concrete for the same reason as the dictation panel's
/// `FirstMouseHostingView`: a generic `NSHostingView` subclass crashes the
/// Release optimizer. First mouse, because Stop & Transcribe has to work on the
/// first click while another app is frontmost.
private final class ConversationHUDHostingView: NSHostingView<ConversationHUDView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The conversation's floating card. A panel of its own, not a mode of the
/// dictation HUD: a dictation taken mid-meeting must never fight it for the
/// window or the position. It never takes key — there is nothing on it to
/// type into — and it only reads `MeetingController` and calls `stop()`.
@MainActor
final class ConversationHUDPanel {
    static let shared = ConversationHUDPanel()

    private var panel: HUDPanel?
    private let state = ConversationHUDState()

    /// Anchored by the card's TOP-centre, just under the menu bar: as far as
    /// the screen allows from the dictation card's bottom-centre home, so the
    /// two never land on each other. Size changes keep that top edge put.
    let placement = HUDPanelPlacement(
        edge: .top,
        anchorsDefaultsKey: "conversation.hud.anchors"
    ) { visible in
        NSPoint(x: visible.midX, y: visible.maxY - HUDMetrics.conversationTopInset)
    }

    private var isObserving = false
    private var defaultsObserver: (any NSObjectProtocol)?
    /// Bumped by every show and every dismissal, so an exit animation that
    /// finishes after the card came back cannot order it out.
    private var presentationTicket = 0

    private init() {}

    // MARK: Observing

    /// Starts following the conversation and the setting. Once, at launch.
    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        // The setting is written by `@AppStorage` in the Conversations pane.
        // Any default changing posts this, so it is a cheap re-read; `sync`
        // does nothing unless the answer differs from what is on screen.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in ConversationHUDPanel.shared.sync() }
        }
        trackNextMeetingChange()
        sync()
    }

    private func trackNextMeetingChange() {
        withObservationTracking {
            let meeting = MeetingController.shared
            _ = meeting.state
            _ = meeting.elapsed
            _ = meeting.levelHistory
            _ = meeting.transcribedChunks
            _ = meeting.totalChunks
        } onChange: { [weak self] in
            // `guard let` first, as in `MenuBarItem`: the Task must capture an
            // immutable reference, not the weak var.
            guard let self else { return }
            // onChange fires *before* the value is written, so read it back on
            // the next main-actor turn — and re-arm, since tracking is one-shot.
            Task { @MainActor in
                self.sync()
                self.trackNextMeetingChange()
            }
        }
    }

    /// Brings the card in line with the conversation and the setting: shown
    /// while one records or transcribes, at the chosen size; gone otherwise —
    /// idle, failed, or importing a file, which gets no card.
    private func sync() {
        let meeting = MeetingController.shared
        let isTranscribing: Bool
        switch meeting.state {
        case .recording: isTranscribing = false
        case .transcribing: isTranscribing = true
        case .idle, .importing, .error:
            dismiss()
            return
        }
        // Checked before mirroring: with the card off, an hour of meter ticks
        // would otherwise re-render a hosting view nobody can see.
        guard let size = ConversationHUDSetting.current.size else {
            dismiss()
            return
        }

        if !isTranscribing { state.levels = meeting.levelHistory }
        state.isTranscribing = isTranscribing
        state.elapsed = meeting.elapsed
        state.transcribedChunks = meeting.transcribedChunks
        state.totalChunks = meeting.totalChunks
        present(size: size)
    }

    // MARK: Presentation

    private func present(size: HUDSize) {
        let panel = ensurePanel()
        let onScreen = panel.isVisible
        let resized = state.size != size
        guard !onScreen || resized || state.isDismissing else { return }

        presentationTicket &+= 1
        if !onScreen || state.isDismissing {
            state.isDismissing = false
            state.presentationCount &+= 1
        }
        state.placedAt = ProcessInfo.processInfo.systemUptime

        // Same clock as the dictation card: the frame starts its morph in the
        // same runloop turn as the card's spring.
        let animate = onScreen && HUDFeatureFlags.morphEnabled
        state.size = size
        let estimate = HUDLayout(recordingAt: size).estimatedCardSize
        placement.expect(cardSize: estimate, animated: animate)
        placement.applyFrame(cardSize: estimate, animated: animate)
        if !onScreen {
            panel.orderFrontRegardless()
            AppLog.hud.info("Conversation HUD shown at \(String(describing: panel.frame))")
        }
    }

    /// Plays the card out on `hudExit`, then orders the panel out — unless the
    /// card came back in the meantime.
    private func dismiss() {
        guard let panel, panel.isVisible, !state.isDismissing else { return }
        presentationTicket &+= 1
        let ticket = presentationTicket
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(Motion.hudExit(reduceMotion: reduceMotion)) {
            state.isDismissing = true
        } completion: { [weak self] in
            guard let self, self.presentationTicket == ticket else { return }
            self.panel?.orderOut(nil)
            self.placement.panelHidden()
        }
    }

    /// Stop & Transcribe. Dropped if the card only just appeared or moved
    /// under the pointer. A stop that ends in an error opens the Conversations
    /// pane, the way the conversation shortcut's does: the card is gone by
    /// then, and the pane is the only place that says what went wrong.
    fileprivate func stopTapped() {
        let sincePlaced = ProcessInfo.processInfo.systemUptime - state.placedAt
        guard sincePlaced >= LiveHUDState.clickGuardAfterModeChange else {
            AppLog.hud.info("Conversation HUD click ignored \(Int(sincePlaced * 1000)) ms after it moved")
            return
        }
        let meeting = MeetingController.shared
        guard meeting.state == .recording else { return }
        Task { @MainActor in
            await meeting.stop()
            if case .error = meeting.state {
                WindowOpener.shared.showMain(section: .meetings)
            }
        }
    }

    private func ensurePanel() -> HUDPanel {
        if let panel { return panel }

        let p = HUDPanel.makeFloating()
        // It floats for the whole meeting — often while the user is sharing
        // their screen — so keep it out of shares and recordings wherever
        // macOS honours that.
        p.sharingType = .none
        let hosting = ConversationHUDHostingView(
            rootView: ConversationHUDView(state: state) { size in
                ConversationHUDPanel.shared.placement.cardSizeChanged(size)
            } onStop: {
                ConversationHUDPanel.shared.stopTapped()
            }
        )
        hosting.frame = NSRect(origin: .zero, size: p.frame.size)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        placement.attach(p)
        panel = p
        return p
    }
}
