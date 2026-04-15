import AppKit
import Observation
import OSLog
import SwiftUI

/// Recording HUD: non-activating, non-key — floats above whatever app the
/// user is typing in without stealing focus.
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Review HUD: accepts key status so the user can actually edit the transcript
/// in a TextEditor before pasting.
private final class KeyAcceptingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum LiveHUDMode {
    case recording
    case reviewing
}

@Observable
@MainActor
final class LiveHUDState {
    static let shared = LiveHUDState()
    var mode: LiveHUDMode = .recording
    var isRecording: Bool = false
    var elapsedSeconds: Double = 0
    /// Smoothed mic level, 0...1.
    var level: Double = 0
    /// Editable transcript bound to the review TextEditor.
    var reviewText: String = ""

    @ObservationIgnored var onPaste: (@MainActor () -> Void)?
    @ObservationIgnored var onCancel: (@MainActor () -> Void)?
}

@MainActor
final class LiveHUDPanel {
    static let shared = LiveHUDPanel()
    private var recordingPanel: NSPanel?
    private var reviewPanel: NSPanel?
    private var previousApp: NSRunningApplication?
    private let state = LiveHUDState.shared

    private let recordingSize = NSSize(width: 320, height: 160)
    private let reviewSize = NSSize(width: 600, height: 320)

    private init() {}

    func show() {
        state.mode = .recording
        state.isRecording = true
        state.elapsedSeconds = 0
        state.level = 0
        state.reviewText = ""
        state.onPaste = nil
        state.onCancel = nil

        let p = ensureRecordingPanel()
        position(p, size: recordingSize)
        p.orderFrontRegardless()
        AppLog.hud.info("HUD shown at \(String(describing: p.frame))")
    }

    func showReview(
        text: String,
        onPaste: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        recordingPanel?.orderOut(nil)

        state.mode = .reviewing
        state.isRecording = false
        state.level = 0
        state.reviewText = text
        state.onPaste = onPaste
        state.onCancel = onCancel

        previousApp = NSWorkspace.shared.frontmostApplication

        let p = ensureReviewPanel()
        position(p, size: reviewSize)
        NSApp.activate()
        p.makeKeyAndOrderFront(nil)
        AppLog.hud.info("HUD review shown at \(String(describing: p.frame))")
    }

    func setElapsed(_ seconds: Double) {
        state.elapsedSeconds = seconds
    }

    func setLevel(_ level: Double) {
        // Exponential smoothing so the orb doesn't jitter on every tap buffer.
        state.level = state.level * 0.6 + level * 0.4
    }

    func hide() {
        state.isRecording = false
        state.level = 0
        state.onPaste = nil
        state.onCancel = nil
        recordingPanel?.orderOut(nil)
        reviewPanel?.orderOut(nil)
    }

    /// Re-activate whatever app was frontmost before the review panel stole focus,
    /// so the simulated Cmd+V lands in the right place.
    func reactivatePreviousApp() {
        previousApp?.activate()
        previousApp = nil
    }

    /// Current edited review text (read at paste time).
    var currentReviewText: String { state.reviewText }

    private func ensureRecordingPanel() -> NSPanel {
        if let recordingPanel { return recordingPanel }

        let initialRect = NSRect(origin: .zero, size: recordingSize)
        let p = NonKeyPanel(
            contentRect: initialRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        configureFloating(p)
        attachHosting(p, rect: initialRect)
        recordingPanel = p
        return p
    }

    private func ensureReviewPanel() -> NSPanel {
        if let reviewPanel { return reviewPanel }

        let initialRect = NSRect(origin: .zero, size: reviewSize)
        let p = KeyAcceptingPanel(
            contentRect: initialRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configureFloating(p)
        attachHosting(p, rect: initialRect)
        reviewPanel = p
        return p
    }

    private func configureFloating(_ p: NSPanel) {
        p.isReleasedWhenClosed = false
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    private func attachHosting(_ p: NSPanel, rect: NSRect) {
        let hosting = NSHostingView(rootView: LiveHUDView(state: state))
        hosting.frame = rect
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.minY + 120
        panel.setFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            display: true,
            animate: false
        )
    }
}

struct LiveHUDView: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        Group {
            switch state.mode {
            case .recording:
                RecordingView(state: state)
            case .reviewing:
                ReviewView(state: state)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 4)
        .padding(20)
    }
}

private struct RecordingView: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        VStack(spacing: 14) {
            VoiceOrb(level: state.level, active: state.isRecording)
                .frame(width: 72, height: 72)

            HStack(spacing: 14) {
                Text(timeString)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()

                Text("⌥Space")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.1)
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    private var timeString: String {
        let total = Int(state.elapsedSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ReviewView: View {
    @Bindable var state: LiveHUDState
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review transcript")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            TextEditor(text: $state.reviewText)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.94))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                )
                .frame(maxHeight: 160)
                .focused($editorFocused)
                .onAppear { editorFocused = true }

            HStack(spacing: 10) {
                Spacer()

                Button {
                    state.onCancel?()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
                .foregroundStyle(.white.opacity(0.82))

                Button {
                    state.onPaste?()
                } label: {
                    HStack(spacing: 8) {
                        Text("Paste")
                        Text("⌥Space")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.36, blue: 0.36))
                )
                .foregroundStyle(.white)
            }
        }
    }
}

/// Single pulsing orb whose scale tracks mic level while recording,
/// and breathes gently when idle.
private struct VoiceOrb: View {
    let level: Double
    let active: Bool

    @State private var idlePulse = false

    private let baseColor = Color(red: 0.95, green: 0.36, blue: 0.36)

    var body: some View {
        let scale = active
            ? 0.55 + min(max(level, 0), 1) * 0.55
            : (idlePulse ? 0.62 : 0.5)

        ZStack {
            Circle()
                .fill(baseColor.opacity(0.18))
                .scaleEffect(scale + 0.35)
                .blur(radius: 10)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [baseColor, baseColor.opacity(0.6)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 36
                    )
                )
                .scaleEffect(scale)
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .animation(
            .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
            value: idlePulse
        )
        .onAppear { idlePulse = true }
    }
}
