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
        p.hasShadow = true
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
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PulseDot(active: state.isRecording)

            Text(state.text.isEmpty ? "Listening…" : state.text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(state.text.isEmpty ? .white.opacity(0.55) : .white)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.15), value: state.text)

            HStack(spacing: 10) {
                Text(timeString)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .monospacedDigit()

                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1, height: 14)

                Text("⌥Space")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.white.opacity(0.08))
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Color(white: 0.10).opacity(0.75))
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 6)
        .padding(6)
    }

    private var timeString: String {
        let total = Int(state.elapsedSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct PulseDot: View {
    let active: Bool
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.55

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(opacity))
                .frame(width: 18, height: 18)
                .scaleEffect(scale)
                .blur(radius: 2)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
        .frame(width: 20, height: 20)
        .onAppear { if active { startPulse() } }
        .onChange(of: active) { _, newValue in
            if newValue { startPulse() }
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            scale = 1.35
            opacity = 0.15
        }
    }
}
