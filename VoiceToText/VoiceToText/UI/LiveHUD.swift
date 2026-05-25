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
    case transcribing
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
    /// One-line notice shown above the review editor when a Resume attempt
    /// silently produced nothing (so failures after API charges stay visible).
    var reviewBanner: String?
    var transcribingElapsedSeconds: Double = 0
    var transcribingProgress: TranscribingProgress?

    /// Cursor position inside the review editor. Written by the editor's
    /// delegate, read by DictationController when Resume is pressed so the
    /// new transcription can be spliced in at the caret.
    @ObservationIgnored var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @ObservationIgnored var onPaste: (@MainActor () -> Void)?
    @ObservationIgnored var onCancel: (@MainActor () -> Void)?
    @ObservationIgnored var onResume: (@MainActor () -> Void)?
}

struct TranscribingProgress: Equatable {
    let current: Int
    let total: Int
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
        reviewPanel?.orderOut(nil)

        state.mode = .recording
        state.isRecording = true
        state.elapsedSeconds = 0
        state.level = 0
        state.levelHistory = Array(repeating: 0, count: LiveHUDState.levelHistoryCount)
        state.reviewText = ""
        state.reviewBanner = nil
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil
        state.selectedRange = NSRange(location: 0, length: 0)
        state.onPaste = nil
        state.onCancel = nil
        state.onResume = nil

        let p = ensureRecordingPanel()
        position(p, size: recordingSize)
        p.orderFrontRegardless()
        AppLog.hud.info("HUD shown at \(String(describing: p.frame))")
    }

    /// Reuses the recording panel (same size/position) for a seamless
    /// hand-off from "recording" to "transcribing".
    func showTranscribing() {
        state.mode = .transcribing
        state.isRecording = false
        state.level = 0
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil

        let p = ensureRecordingPanel()
        position(p, size: recordingSize)
        p.orderFrontRegardless()
    }

    func showReview(
        text: String,
        cursorLocation: Int? = nil,
        banner: String? = nil,
        onPaste: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onResume: @escaping @MainActor () -> Void
    ) {
        recordingPanel?.orderOut(nil)

        let nsLen = (text as NSString).length
        let caret = max(0, min(cursorLocation ?? nsLen, nsLen))

        state.mode = .reviewing
        state.isRecording = false
        state.level = 0
        state.reviewText = text
        state.reviewBanner = banner
        state.selectedRange = NSRange(location: caret, length: 0)
        state.onPaste = onPaste
        state.onCancel = onCancel
        state.onResume = onResume

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

    func setTranscribingElapsed(_ seconds: Double) {
        state.transcribingElapsedSeconds = seconds
    }

    func setTranscribingProgress(current: Int, total: Int) {
        state.transcribingProgress = TranscribingProgress(current: current, total: total)
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
        state.reviewBanner = nil
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil
        state.onPaste = nil
        state.onCancel = nil
        state.onResume = nil
        recordingPanel?.orderOut(nil)
        reviewPanel?.orderOut(nil)
    }

    /// Current edited review text (read at paste time).
    var currentReviewText: String { state.reviewText }

    /// Current caret position inside the review editor (read at resume time
    /// to decide where to splice the next transcription).
    var currentCursorLocation: Int { state.selectedRange.location }

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
            case .transcribing:
                TranscribingView(state: state)
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

                Text(recordingHint)
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

    private var recordingHint: String {
        switch HotkeyStore.shared.mode {
        case .hold: return "Release to finish · Esc cancels"
        case .toggle: return "Press again to finish · Esc cancels"
        }
    }
}

private struct TranscribingView: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        VStack(spacing: 14) {
            PulsingDots()
                .frame(height: 14)

            ShimmerText("Transcribing")
                .font(.system(size: 14, weight: .medium))

            HStack(spacing: 10) {
                if let progress = state.transcribingProgress {
                    Text("\(progress.current) / \(progress.total)")
                }
                Text(elapsedString)
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var elapsedString: String {
        String(format: "%0.1fs", state.transcribingElapsedSeconds)
    }
}

private struct PulsingDots: View {
    @State private var phase: Double = 0

    private static let dotCount = 3
    private static let dotSize: CGFloat = 8
    private static let dotSpacing: CGFloat = 10
    private static let cycleDuration: TimeInterval = 1.2

    var body: some View {
        HStack(spacing: Self.dotSpacing) {
            ForEach(0..<Self.dotCount, id: \.self) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .opacity(opacity(at: index))
                    .scaleEffect(scale(at: index))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: Self.cycleDuration).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    // Per-dot phase offset makes the highlight travel left → right;
    // the triangle shape smooths the cycle.
    private func wave(at index: Int) -> Double {
        let offset = Double(index) / Double(Self.dotCount)
        let p = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return 1 - abs(p - 0.5) * 2
    }

    private func opacity(at index: Int) -> Double {
        0.25 + 0.7 * wave(at: index)
    }

    private func scale(at index: Int) -> Double {
        0.8 + 0.4 * wave(at: index)
    }
}

private struct ShimmerText: View {
    let text: String
    @State private var phase: CGFloat = -1

    init(_ text: String) { self.text = text }

    private static let cycleDuration: TimeInterval = 1.8
    private static let baseOpacity: Double = 0.4

    var body: some View {
        Text(text)
            .foregroundStyle(.white.opacity(Self.baseOpacity))
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0.95), location: 0.5),
                            .init(color: .white.opacity(0), location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: geo.size.width * phase)
                    .mask(
                        Text(text)
                            .frame(width: geo.size.width, alignment: .leading)
                    )
                }
            )
            .onAppear {
                withAnimation(.linear(duration: Self.cycleDuration).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

private struct ReviewView: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let banner = state.reviewBanner {
                ReviewBanner(message: banner)
            }

            ReviewTextEditor(text: $state.reviewText, state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 8) {
                ReviewKeyButton(
                    title: "Resume",
                    systemImage: "mic.fill",
                    hint: "⌘R",
                    emphasis: .secondary
                ) { state.onResume?() }

                Spacer()

                ReviewKeyButton(
                    title: "Cancel",
                    hint: "esc",
                    emphasis: .secondary
                ) { state.onCancel?() }

                ReviewKeyButton(
                    title: "Paste",
                    hint: HotkeyStore.shared.binding.displayKeys.joined(),
                    emphasis: .primary
                ) { state.onPaste?() }
            }
        }
    }
}

/// NSTextView-backed editor: we need the caret position when Resume is
/// pressed so the next transcription can be spliced in at the cursor.
/// SwiftUI's TextEditor doesn't expose a selection binding on macOS in a way
/// that survives panel focus changes, so we wrap an NSTextView directly.
private struct ReviewTextEditor: NSViewRepresentable {
    @Binding var text: String
    let state: LiveHUDState

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        Self.configureScrollView(scrollView)
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        Self.configureTextView(textView, delegate: context.coordinator)
        textView.string = text
        textView.setSelectedRange(clampedRange(state.selectedRange, in: text))
        context.coordinator.lastSyncedText = text
        focusOnNextRunLoop(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Skip resync when nothing came in from the outside — otherwise we'd
        // clobber the user's caret on every keystroke (textDidChange writes
        // through the binding, which triggers updateNSView).
        guard textView.string != text, context.coordinator.lastSyncedText != text else {
            return
        }
        textView.string = text
        textView.setSelectedRange(clampedRange(state.selectedRange, in: text))
        context.coordinator.lastSyncedText = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func clampedRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = max(0, min(range.location, length))
        let extent = max(0, min(range.length, length - location))
        return NSRange(location: location, length: extent)
    }

    private func focusOnNextRunLoop(_ textView: NSTextView) {
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
    }

    private static func configureTextView(_ textView: NSTextView, delegate: NSTextViewDelegate) {
        textView.delegate = delegate
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = .systemBlue
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
    }

    private static func configureScrollView(_ scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReviewTextEditor
        /// Last text we either sent to or received from the NSTextView.
        /// Lets `updateNSView` distinguish "user just typed" from "binding
        /// changed externally" and skip self-inflicted refreshes.
        var lastSyncedText: String = ""

        init(parent: ReviewTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            lastSyncedText = textView.string
            parent.text = textView.string
            parent.state.selectedRange = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.state.selectedRange = textView.selectedRange()
        }
    }
}

private struct ReviewBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.85))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35))
        )
    }
}

private struct ReviewKeyButton: View {
    enum Emphasis { case primary, secondary }

    let title: String
    let systemImage: String?
    let hint: String
    let emphasis: Emphasis
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        hint: String,
        emphasis: Emphasis,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.hint = hint
        self.emphasis = emphasis
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .accessibilityLabel(title)
                } else {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
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
