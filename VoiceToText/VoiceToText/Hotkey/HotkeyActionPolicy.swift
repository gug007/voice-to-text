import Foundation

enum RecordingShortcutMode: String, Codable, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hold: return "Hold to record"
        case .toggle: return "Press to toggle"
        }
    }
}

enum DictationHotkeyEvent {
    case pressed
    case released
    case escape
}

enum DictationHotkeyState {
    case idle
    case preparing
    case recording
    case transcribing
    case reviewing
    case error
}

enum DictationHotkeyAction: Equatable {
    case none
    case startRecording
    case stopAndTranscribe
    case confirmPaste
    case cancelRecording
    case cancelPendingRecording
}

enum DictationHotkeyPolicy {
    static func action(
        mode: RecordingShortcutMode,
        state: DictationHotkeyState,
        event: DictationHotkeyEvent
    ) -> DictationHotkeyAction {
        if event == .escape {
            return state == .recording ? .cancelRecording : .none
        }

        switch mode {
        case .hold:
            return holdAction(state: state, event: event)
        case .toggle:
            return toggleAction(state: state, event: event)
        }
    }

    private static func holdAction(
        state: DictationHotkeyState,
        event: DictationHotkeyEvent
    ) -> DictationHotkeyAction {
        switch (state, event) {
        case (.idle, .pressed), (.error, .pressed):
            return .startRecording
        case (.preparing, .released):
            return .cancelPendingRecording
        case (.recording, .released):
            return .stopAndTranscribe
        case (.reviewing, .pressed):
            return .confirmPaste
        default:
            return .none
        }
    }

    private static func toggleAction(
        state: DictationHotkeyState,
        event: DictationHotkeyEvent
    ) -> DictationHotkeyAction {
        guard event == .pressed else { return .none }

        switch state {
        case .idle, .error:
            return .startRecording
        case .recording:
            return .stopAndTranscribe
        case .reviewing:
            return .confirmPaste
        case .preparing, .transcribing:
            return .none
        }
    }
}
