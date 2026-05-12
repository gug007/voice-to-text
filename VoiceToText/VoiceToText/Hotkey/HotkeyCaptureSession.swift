import AppKit
import Carbon.HIToolbox

enum HotkeyCaptureOutcome: Equatable {
    case ignored
    case pendingStandaloneModifier
    case captured(HotkeyBinding)
    case cancelled
    case rejected(String)
}

struct HotkeyCaptureSession {
    private var pendingStandaloneModifier: HotkeyBinding?

    mutating func reset() {
        pendingStandaloneModifier = nil
    }

    mutating func handle(event: NSEvent) -> HotkeyCaptureOutcome {
        switch event.type {
        case .flagsChanged:
            return handleModifierEvent(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            return .ignored
        }
    }

    private mutating func handleKeyDown(_ event: NSEvent) -> HotkeyCaptureOutcome {
        pendingStandaloneModifier = nil

        let pureModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Escape) && pureModifiers.isEmpty {
            return .cancelled
        }

        let candidate = HotkeyBinding.fromEvent(event)
        guard candidate.modifiers != 0 || candidate.isFunctionKey || candidate.isStandaloneModifier else {
            return .rejected("Add at least one modifier (⌘ ⌥ ⌃ ⇧), pick a function key, or press Right Control.")
        }

        return .captured(candidate)
    }

    private mutating func handleModifierEvent(_ event: NSEvent) -> HotkeyCaptureOutcome {
        guard let candidate = HotkeyBinding.fromModifierEvent(event) else { return .ignored }

        if event.modifierFlags.contains(.control) {
            pendingStandaloneModifier = candidate
            return .pendingStandaloneModifier
        }

        guard pendingStandaloneModifier == candidate else { return .ignored }
        pendingStandaloneModifier = nil
        return .captured(candidate)
    }
}
