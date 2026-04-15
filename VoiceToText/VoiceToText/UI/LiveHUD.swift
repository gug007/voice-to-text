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
    var isRecording: Bool = false
    var elapsedSeconds: Double = 0
    /// Smoothed mic level, 0...1.
    var level: Double = 0
}

@MainActor
final class LiveHUDPanel {
    static let shared = LiveHUDPanel()
    private var panel: NSPanel?
    private let state = LiveHUDState.shared

    private let fixedWidth: CGFloat = 320
    private let fixedHeight: CGFloat = 160

    private init() {}

    func show() {
        state.isRecording = true
        state.elapsedSeconds = 0
        state.level = 0

        let p = ensurePanel()
        position(p)
        p.orderFrontRegardless()
        AppLog.hud.info("HUD shown at \(String(describing: p.frame))")
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
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let initialRect = NSRect(x: 0, y: 0, width: fixedWidth, height: fixedHeight)

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

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - fixedWidth / 2
        let y = screenFrame.minY + 120
        panel.setFrame(
            NSRect(x: x, y: y, width: fixedWidth, height: fixedHeight),
            display: true,
            animate: false
        )
    }
}

struct LiveHUDView: View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 4)
        .padding(20)
    }

    private var timeString: String {
        let total = Int(state.elapsedSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
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
