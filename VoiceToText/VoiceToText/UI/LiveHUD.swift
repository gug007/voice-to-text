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

/// Review HUD: nonactivating (doesn't bring our Settings window forward with it)
/// but still accepts key status so the user can edit the transcript in a TextEditor.
/// Same pattern as Spotlight/Raycast.
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
    static let levelHistoryCount = 140

    var mode: LiveHUDMode = .recording
    var isRecording: Bool = false
    var elapsedSeconds: Double = 0
    /// Smoothed mic level, 0...1.
    var level: Double = 0
    /// Rolling buffer of recent levels for the ECG trace (oldest → newest).
    var levelHistory: [Double] = Array(repeating: 0, count: LiveHUDState.levelHistoryCount)
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
    private let state = LiveHUDState.shared

    private let recordingSize = NSSize(width: 480, height: 150)
    private let reviewSize = NSSize(width: 560, height: 260)

    private init() {}

    func show() {
        state.mode = .recording
        state.isRecording = true
        state.elapsedSeconds = 0
        state.level = 0
        state.levelHistory = Array(repeating: 0, count: LiveHUDState.levelHistoryCount)
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

        let p = ensureReviewPanel()
        position(p, size: reviewSize)
        // Nonactivating panel: becomes key for keyboard input without activating
        // our app, so the Settings window stays wherever the user left it.
        p.orderFrontRegardless()
        p.makeKeyAndOrderFront(nil)
        AppLog.hud.info("HUD review shown at \(String(describing: p.frame))")
    }

    func setElapsed(_ seconds: Double) {
        state.elapsedSeconds = seconds
    }

    func setLevel(_ level: Double) {
        // Exponential smoothing so the trace doesn't jitter on every tap buffer.
        let smoothed = state.level * 0.6 + level * 0.4
        state.level = smoothed

        var history = state.levelHistory
        history.removeFirst()
        history.append(smoothed)
        state.levelHistory = history
    }

    func hide() {
        state.isRecording = false
        state.level = 0
        state.onPaste = nil
        state.onCancel = nil
        recordingPanel?.orderOut(nil)
        reviewPanel?.orderOut(nil)
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
            styleMask: [.nonactivatingPanel, .borderless],
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
        VStack(spacing: 10) {
            ECGTrace(samples: state.levelHistory)
                .frame(maxWidth: .infinity)
                .frame(height: 72)

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
        VStack(alignment: .leading, spacing: 16) {
            TextEditor(text: $state.reviewText)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.92))
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focused($editorFocused)
                .onAppear { editorFocused = true }

            HStack(spacing: 8) {
                Spacer()

                ReviewKeyButton(
                    title: "Cancel",
                    hint: "esc",
                    emphasis: .secondary
                ) { state.onCancel?() }

                ReviewKeyButton(
                    title: "Paste",
                    hint: "⌥Space",
                    emphasis: .primary
                ) { state.onPaste?() }
            }
        }
    }
}

private struct ReviewKeyButton: View {
    enum Emphasis { case primary, secondary }

    let title: String
    let hint: String
    let emphasis: Emphasis
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(hint)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(emphasis == .primary ? 0.55 : 0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(.white.opacity(emphasis == .primary ? 0.96 : 0.72))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(emphasis == .primary ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(emphasis == .primary ? 0.18 : 0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Minimal scrolling envelope ribbon: the mic level mirrored above and below a
/// center line, filled as a single shape. A tiny floor keeps a thin ribbon
/// visible when silent. Left edge fades out, right edge is the write head.
private struct ECGTrace: View {
    let samples: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard samples.count > 1 else { return }

            let midY = size.height / 2
            let amp = size.height * 0.48
            let floor: CGFloat = 1.2
            let stepX = size.width / CGFloat(samples.count - 1)

            func offset(_ s: Double) -> CGFloat {
                let clamped = min(max(s, 0), 1)
                return max(floor, CGFloat(clamped) * amp)
            }

            var path = Path()
            // Upper edge, left → right.
            for i in 0..<samples.count {
                let x = CGFloat(i) * stepX
                let y = midY - offset(samples[i])
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            // Lower edge, right → left, closing the ribbon.
            for i in stride(from: samples.count - 1, through: 0, by: -1) {
                let x = CGFloat(i) * stepX
                let y = midY + offset(samples[i])
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.closeSubpath()

            ctx.fill(path, with: .color(.white.opacity(0.85)))
        }
        .mask(
            LinearGradient(
                colors: [.clear, .white],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .animation(.linear(duration: 0.08), value: samples)
    }
}
