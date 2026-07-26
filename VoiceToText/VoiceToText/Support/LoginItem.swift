import Foundation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class LoginItemController {
    static let shared = LoginItemController()

    private(set) var isEnabled: Bool
    private(set) var requiresApproval: Bool
    private(set) var lastError: String?

    private init() {
        let status = SMAppService.mainApp.status
        self.isEnabled = status == .enabled
        self.requiresApproval = status == .requiresApproval
    }

    /// Turns launch-at-login on the first time the app runs: a hotkey-driven
    /// dictation app is useless when it isn't running, and the toggle is easy to
    /// never find. Applied exactly once and recorded, so a user who switches it
    /// back off is never overridden on the next launch — and a one-shot attempt
    /// means a failure can't turn into a login item we keep re-forcing.
    func applyDefaultIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.defaultAppliedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.defaultAppliedKey)
        // Only `.notRegistered` is ours to change. `.enabled` is already there,
        // and `.requiresApproval` means the user turned it off in System
        // Settings — registering again would fight them.
        guard SMAppService.mainApp.status == .notRegistered else { return }
        setEnabled(true)
    }

    private static let defaultAppliedKey = "loginItem.defaultApplied"

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
