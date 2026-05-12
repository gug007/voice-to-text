import AppKit
import Carbon.HIToolbox
import IOKit.hidsystem

enum HotkeyCaptureOutcome: Equatable {
    case ignored
    case pendingStandaloneModifier
    case captured(HotkeyBinding)
    case cancelled
    case rejected(String)
}

struct HotkeyCaptureSession {
    private var pendingStandaloneModifier: HotkeyBinding?
    private var suppressStandaloneModifierUntilRelease = false
    private var captureIsComplete = false

    mutating func reset() {
        pendingStandaloneModifier = nil
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

        let candidate = HotkeyBinding.fromEvent(event)
        guard candidate.modifiers != 0 || candidate.isFunctionKey || candidate.isStandaloneModifier else {
            return .rejected("Add at least one modifier (⌘ ⌥ ⌃ ⇧), pick a function key, or press Right Control.")
        }

        captureIsComplete = true
        return .captured(candidate)
    }

    private mutating func handleModifierEvent(_ event: NSEvent) -> HotkeyCaptureOutcome {
        if suppressStandaloneModifierUntilRelease {
            if event.keyCode == UInt16(kVK_RightControl) {
                suppressStandaloneModifierUntilRelease = false
            }
            return .ignored
        }

        let nonControlModifiers = event.modifierFlags.intersection([.command, .option, .shift])
        let leftControlIsDown = event.modifierFlags.rawValue & UInt(NX_DEVICELCTLKEYMASK) != 0
        let rightControlIsDown = event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
        if event.keyCode == UInt16(kVK_RightControl),
           rightControlIsDown,
           (!nonControlModifiers.isEmpty || leftControlIsDown) {
            pendingStandaloneModifier = nil
            suppressStandaloneModifierUntilRelease = true
            return .ignored
        }

        if pendingStandaloneModifier != nil,
           event.keyCode != UInt16(kVK_RightControl) {
            pendingStandaloneModifier = nil
            suppressStandaloneModifierUntilRelease = true
            return .ignored
        }

        guard let candidate = HotkeyBinding.fromModifierEvent(event) else { return .ignored }

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
