import Foundation

/// The single source for every string that tells the user to go to System
/// Settings. Card subtitles and alert bodies used to spell the path out
/// independently — which is how "Privacy & Security → Microphone" and
/// "Privacy → Microphone" ended up in the same pane. Nothing outside this enum
/// may type that path again.
nonisolated enum PermissionCopy {

    // MARK: The path

    /// The alert's confirming button.
    static let openSystemSettingsButton = "Open System Settings"
    /// The compact button used inside a status row, where the row's title
    /// already says which permission is meant.
    static let openSettingsShortButton = "Open Settings…"

    /// "Open System Settings → Privacy & Security → <pane> and enable VoiceToText."
    static func enableInstruction(pane: String) -> String {
        "Open System Settings → Privacy & Security → \(pane) and enable VoiceToText."
    }

    // MARK: Microphone

    static let microphoneTitle = "Microphone"
    static let microphoneAlertTitle = "Microphone Access Required"
    static let microphonePurpose = "VoiceToText needs permission to record audio for transcription."
    static let microphoneGranted = "VoiceToText can record from your microphone."
    static let microphoneNotDetermined = "Click Request to grant microphone access."
    static let microphoneRequestButton = "Request…"
    static var microphoneEnable: String { enableInstruction(pane: "Microphone") }
    static var microphoneDenied: String { "Denied. \(microphoneEnable)" }
    static var microphoneAlertBody: String { "\(microphonePurpose) \(microphoneEnable)" }

    // MARK: Accessibility

    static let accessibilityTitle = "Accessibility"
    static let accessibilityAlertTitle = "Accessibility Access Required"
    /// The one phrase both the card subtitle and the alert body build on.
    static let accessibilityReason = "global shortcuts, Esc cancel, and typing text into other apps"
    static var accessibilityPurpose: String { "Required for \(accessibilityReason)." }
    static var accessibilityEnable: String { enableInstruction(pane: "Accessibility") }
    static var accessibilityAlertBody: String {
        "VoiceToText needs Accessibility permission for \(accessibilityReason). \(accessibilityEnable)"
    }

    // MARK: Input Monitoring (standalone Right Control)

    static let inputMonitoringNeeded =
        "Right Control needs Input Monitoring permission. Enable VoiceToText in System Settings, then return here."

    // MARK: Screen Recording (Conversations)

    static let screenRecordingTitle = "Screen Recording permission needed"
    static let screenRecordingPurpose =
        "Capturing other participants' audio uses Screen Recording. VoiceToText never records the screen — only the audio."
}
