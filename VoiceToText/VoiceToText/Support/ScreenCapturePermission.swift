import AppKit

/// Screen Recording (TCC) permission, required by ScreenCaptureKit to capture
/// system audio for meeting recording. Mirrors the other permission helpers.
enum ScreenCapturePermission {
    /// True when the app may capture screen content / system audio. Does not
    /// prompt — safe to poll from the UI.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the one-time system prompt (no-op on later calls — macOS then
    /// just returns the current status). Returns whether access is granted.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
