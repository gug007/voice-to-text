import Observation

/// Lets code outside the window ask `SettingsView` to show a particular pane.
///
/// `SettingsView` owns its own `selection`, and the window may not exist yet
/// when the request is made — the dictation failure card's "Add API Key" is the
/// case that matters. So the section is parked here, and `SettingsView` picks it
/// up whether it is already on screen or about to be created by `openWindow`.
@Observable
@MainActor
final class SettingsRouter {
    static let shared = SettingsRouter()

    var pendingSection: SettingsView.Section?

    private init() {}
}
