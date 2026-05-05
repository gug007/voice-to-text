import AppKit
import AVFoundation
import Combine
import SwiftUI

@main
struct VoiceToTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var registry = ModelRegistry.shared

    init() {
        UserDefaults.standard.register(defaults: ["review.beforePaste": true])
        DictationController.shared.installHotkey()
        ModelRegistry.shared.bootstrapActiveModelIfNeeded()
        Task { await AppUpdater.shared.autoCheckLoop() }
    }

    var body: some Scene {
        Window("VoiceToText", id: WindowID.main) {
            MainWindowView(registry: registry)
        }
        .defaultSize(width: 820, height: 600)
        .windowResizability(.contentMinSize)
    }
}

struct MainWindowView: View {
    let registry: ModelRegistry
    @Environment(\.openWindow) private var openWindow
    @State private var micStatus = MicPermission.status

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if micStatus == .authorized {
                SettingsView(registry: registry)
            } else {
                PermissionGateView()
            }
        }
        .task {
            WindowOpener.shared.openMain = { [openWindow] in
                openWindow(id: WindowID.main)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .onReceive(refreshTimer) { _ in micStatus = MicPermission.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            micStatus = MicPermission.status
        }
    }
}

@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var openMain: (() -> Void)?
    private init() {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var wasLaunchedAtLogin = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let isDefault = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool {
            Self.wasLaunchedAtLogin = !isDefault
        }
        guard Self.wasLaunchedAtLogin else { return }
        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeKey {
                window.orderOut(nil)
            }
            NSApp.deactivate()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            WindowOpener.shared.openMain?()
        }
        return true
    }
}
