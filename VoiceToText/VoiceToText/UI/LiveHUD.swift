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

    private let fixedWidth: CGFloat = 560
    private let minHeight: CGFloat = 64

    private init() {}

    func show() {
        state.text = ""
        state.isRecording = true
        state.elapsedSeconds = 0

        let p = ensurePanel()
        resizeToFit(p)
        positionAtBottomCenter(p)
        p.orderFrontRegardless()
        AppLog.hud.info("HUD shown at \(String(describing: p.frame))")
    }

    func update(text: String) {
        state.text = text
        guard let panel else { return }
        resizeToFit(panel)
        positionAtBottomCenter(panel)
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

    private func resizeToFit(_ panel: NSPanel) {
        guard let hosting = panel.contentView else { return }
        hosting.layoutSubtreeIfNeeded()
        let intrinsic = hosting.intrinsicContentSize.height
        let fitting = hosting.fittingSize.height
        let target = max(minHeight, max(intrinsic, fitting))
        let oldFrame = panel.frame
        let newFrame = NSRect(
            x: oldFrame.origin.x,
            y: oldFrame.origin.y,
            width: fixedWidth,
            height: target
        )
        panel.setFrame(newFrame, display: true, animate: false)
    }

    private func positionAtBottomCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = panel.frame
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.minY + 120
        panel.setFrame(NSRect(x: x, y: y, width: frame.width, height: frame.height), display: true)
    }
}

struct LiveHUDView: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            WaveformIndicator(active: state.isRecording)

            Text(state.text.isEmpty ? "Listening" : state.text)
                .font(.system(size: 13.5, weight: .medium))
                .kerning(-0.1)
                .foregroundStyle(state.text.isEmpty ? Color.white.opacity(0.48) : Color.white.opacity(0.95))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.15), value: state.text)

            HStack(spacing: 10) {
                Text(timeString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()

                Text("⌥ Space")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.09))
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(white: 0.06).opacity(0.96))
        )
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
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
