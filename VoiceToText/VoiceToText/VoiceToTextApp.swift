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

    private var launchedAt = Date()
    // A voicetotext:// trigger is a background dictation action: it must never
    // surface the settings window or steal focus from the app the transcript
    // will be typed into. We remember when one last arrived so the reopen that
    // a URL open can generate doesn't pop the UI.
    private var lastExternalCommandAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchedAt = Date()
        Self.wasLaunchedAtLogin = LaunchContext.shouldHideMainWindowOnLaunch(
            appleEvent: NSAppleEventManager.shared().currentAppleEvent,
            launchUserInfo: notification.userInfo
        )
        guard Self.wasLaunchedAtLogin else { return }
        hideMainWindows()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A reopen fired as a side effect of a voicetotext:// trigger must stay
        // headless — don't bring up the settings window.
        if Date().timeIntervalSince(lastExternalCommandAt) < 2 {
            return true
        }
        Task { @MainActor in
            WindowOpener.shared.openMain?()
        }
        return true
    }

    /// Handle `voicetotext://` URLs opened by other apps so a button elsewhere
    /// can trigger dictation. Callers should open the URL without activating
    /// VoiceToText (NSWorkspace.OpenConfiguration.activates = false, or
    /// `open -g`) so the transcript pastes into their app, which stays frontmost.
    func application(_ application: NSApplication, open urls: [URL]) {
        let commandURLs = urls.filter { $0.scheme?.lowercased() == AppURLScheme.scheme }
        guard !commandURLs.isEmpty else { return }
        lastExternalCommandAt = Date()
        // A cold launch triggered by the URL auto-opens the settings window;
        // hide it so the trigger stays a headless, background action.
        if Date().timeIntervalSince(launchedAt) < 3 {
            hideMainWindows()
        }
        for url in commandURLs {
            DictationController.shared.handleExternalCommand(DictationController.ExternalCommand(url: url))
        }
    }

    private func hideMainWindows() {
        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeKey {
                window.orderOut(nil)
            }
            NSApp.deactivate()
        }
    }
}
