import Foundation

/// What a conversation-shortcut press should do, as a function of the meeting
/// controller's state alone. Deliberately simpler than `DictationHotkeyPolicy`:
/// the conversation shortcut is press-only (no hold mode) and has no review or
/// preparing phase to arbitrate.
nonisolated enum MeetingHotkeyState {
    case idle
    case recording
    /// Transcribing, importing, or mid start/stop transition — a press here
    /// would race work already in flight, so it is swallowed.
    case busy
}

nonisolated enum MeetingHotkeyAction: Equatable {
    case none
    case start
    case stopAndTranscribe
}

nonisolated enum MeetingHotkeyPolicy {
    static func action(state: MeetingHotkeyState) -> MeetingHotkeyAction {
        switch state {
        case .idle: return .start
        case .recording: return .stopAndTranscribe
        case .busy: return .none
        }
    }
}
