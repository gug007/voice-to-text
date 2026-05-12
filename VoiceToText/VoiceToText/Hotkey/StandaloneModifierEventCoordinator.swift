import Foundation

struct StandaloneModifierEventCoordinator {
    private var pendingToggleStop = false

    mutating func normalize(
        event: DictationHotkeyEvent,
        mode: RecordingShortcutMode,
        state: DictationHotkeyState
    ) -> [DictationHotkeyEvent] {
        switch event {
        case .standalonePressed:
            if mode == .toggle, state == .recording {
                pendingToggleStop = true
                return []
            }
            return [.pressed]

        case .standaloneReleased:
            if pendingToggleStop {
                pendingToggleStop = false
                return [.pressed]
            }
            return mode == .hold ? [.released] : []

        case .cancel:
            if pendingToggleStop {
                pendingToggleStop = false
                return []
            }
            return [.cancel]

        case .pressed, .released, .escape:
            return [event]
        }
    }

    mutating func reset() {
        pendingToggleStop = false
    }
}
