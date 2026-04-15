import AppKit
import Observation
import OSLog
import SwiftUI

/// NSPanel subclass that refuses key/main status so macOS Tahoe doesn't draw
/// a focus halo around our borderless floating HUD.
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@Observable
@MainActor
final class LiveHUDState {
    static let shared = LiveHUDState()
    var text: String = ""
    var isRecording: Bool = false
    var elapsedSeconds: Double = 0
}

@MainActor
final class LiveHUDPanel {
    static let shared = LiveHUDPanel()
    private var panel: NSPanel?
    private let state = LiveHUDState.shared

    private let fixedWidth: CGFloat = 860
    private let minHeight: CGFloat = 104
    private let maxHeight: CGFloat = 300
    private var lockedHeight: CGFloat = 104

    private init() {}

    func show() {
        state.text = ""
        state.isRecording = true
        state.elapsedSeconds = 0
        lockedHeight = minHeight

        let p = ensurePanel()
        resizeAndPosition(p)
        p.orderFrontRegardless()
        AppLog.hud.info("HUD shown at \(String(describing: p.frame))")
    }

    func update(text: String) {
        state.text = text
        guard let panel else { return }
        resizeAndPosition(panel)
    }

    func setElapsed(_ seconds: Double) {
        state.elapsedSeconds = seconds
    }

    func hide() {
        state.isRecording = false
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let initialRect = NSRect(x: 0, y: 0, width: fixedWidth, height: minHeight)

        let p = NonKeyPanel(
            contentRect: initialRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isReleasedWhenClosed = false
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let hosting = NSHostingView(rootView: LiveHUDView(state: state))
        hosting.frame = initialRect
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        self.panel = p
        return p
    }

    private func resizeAndPosition(_ panel: NSPanel) {
        guard let hosting = panel.contentView else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize.height
        let wanted = max(minHeight, min(maxHeight, fitting))
        lockedHeight = max(lockedHeight, wanted)

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - fixedWidth / 2
        let y = screenFrame.minY + 120
        panel.setFrame(
            NSRect(x: x, y: y, width: fixedWidth, height: lockedHeight),
            display: true,
            animate: false
        )
    }
}

struct LiveHUDView: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            WaveformIndicator(active: state.isRecording)
                .padding(.top, 2)

            Text(state.text.isEmpty ? "Listening" : state.text)
                .font(.system(size: 16, weight: .medium))
                .kerning(-0.1)
                .foregroundStyle(state.text.isEmpty ? Color.white.opacity(0.48) : Color.white.opacity(0.95))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.15), value: state.text)

            HStack(spacing: 12) {
                Text(timeString)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()

                Text("⌥ Space")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.09))
                    )
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
        )
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 6)
        .padding(28)
    }

    private var timeString: String {
        let total = Int(state.elapsedSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct WaveformIndicator: View {
    let active: Bool
    @State private var animating = false

    private let barCount = 4
    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 2.5
    private let maxHeight: CGFloat = 16

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(Color(red: 1.0, green: 0.32, blue: 0.32))
                    .frame(width: barWidth, height: maxHeight)
                    .scaleEffect(y: animating ? 1.0 : 0.3, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.11),
                        value: animating
                    )
            }
        }
        .frame(width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing, height: maxHeight)
        .onAppear { if active { animating = true } }
        .onChange(of: active) { _, v in animating = v }
    }
}
