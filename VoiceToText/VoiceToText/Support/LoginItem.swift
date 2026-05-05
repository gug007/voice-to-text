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
