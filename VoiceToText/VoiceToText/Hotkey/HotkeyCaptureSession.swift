import AppKit
import Carbon.HIToolbox
import IOKit.hidsystem

enum HotkeyCaptureOutcome: Equatable {
    case ignored
    case pendingStandaloneModifier
    case captured(HotkeyBinding)
    case cancelled
}

struct HotkeyCaptureSession {
    private var pendingStandaloneModifier: HotkeyBinding?
    private var pendingKeyBinding: HotkeyBinding?
    private var suppressStandaloneModifierUntilRelease = false
    private var captureIsComplete = false

    mutating func reset() {
        pendingStandaloneModifier = nil
        pendingKeyBinding = nil
        suppressStandaloneModifierUntilRelease = false
        captureIsComplete = false
    }

    mutating func handle(event: NSEvent) -> HotkeyCaptureOutcome {
        guard !captureIsComplete else { return .ignored }

        switch event.type {
        case .flagsChanged:
            return handleModifierEvent(event)
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        default:
            return .ignored
        }
    }

    private mutating func handleKeyDown(_ event: NSEvent) -> HotkeyCaptureOutcome {
        pendingStandaloneModifier = nil
        suppressStandaloneModifierUntilRelease = false

        let pureModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Escape) && pureModifiers.isEmpty {
            captureIsComplete = true
            return .cancelled
        }

        pendingKeyBinding = HotkeyBinding.fromEvent(event)
        return .ignored
    }

    private mutating func handleKeyUp(_ event: NSEvent) -> HotkeyCaptureOutcome {
        guard let candidate = pendingKeyBinding else { return .ignored }
        guard candidate.keyCode == UInt32(event.keyCode) else { return .ignored }

        pendingKeyBinding = nil
        captureIsComplete = true
        return .captured(candidate)
    }

    private mutating func handleModifierEvent(_ event: NSEvent) -> HotkeyCaptureOutcome {
        if suppressStandaloneModifierUntilRelease {
            if let pendingStandaloneModifier,
               HotkeyBinding.isReleaseOfModifier(pendingStandaloneModifier, event: event) {
                suppressStandaloneModifierUntilRelease = false
                self.pendingStandaloneModifier = nil
            }
            return .ignored
        }

        if let pendingStandaloneModifier,
           HotkeyBinding.isReleaseOfModifier(pendingStandaloneModifier, event: event) {
            self.pendingStandaloneModifier = nil
            captureIsComplete = true
            return .captured(pendingStandaloneModifier)
        }

        if let pendingStandaloneModifier,
           let candidate = HotkeyBinding.fromModifierEvent(event),
           candidate != pendingStandaloneModifier,
           HotkeyBinding.modifierIsDown(candidate, in: event) {
            suppressStandaloneModifierUntilRelease = true
            return .ignored
        }

        guard let candidate = HotkeyBinding.fromModifierEvent(event) else { return .ignored }
        guard HotkeyBinding.modifierIsDown(candidate, in: event) else { return .ignored }

        if HotkeyBinding.otherModifiersAreDown(than: candidate, in: event) {
            pendingStandaloneModifier = candidate
            suppressStandaloneModifierUntilRelease = true
            return .ignored
        }

        if pendingStandaloneModifier == nil {
            pendingStandaloneModifier = candidate
            return .pendingStandaloneModifier
        }

        guard pendingStandaloneModifier == candidate else { return .ignored }
        pendingStandaloneModifier = nil
        captureIsComplete = true
        return .captured(candidate)
    }
}
