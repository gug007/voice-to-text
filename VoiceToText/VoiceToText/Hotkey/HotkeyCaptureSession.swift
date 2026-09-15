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
    /// A binding this capture must refuse, paired with the reason to show. Used
    /// to keep the dictation and conversation shortcuts off each other's keys.
    struct ReservedBinding: Equatable {
        let binding: HotkeyBinding
        let message: String

        init(binding: HotkeyBinding, message: String) {
            self.binding = binding
            self.message = message
        }
    }

    /// False for the conversation shortcut: standalone Right Control needs the
    /// single CGEvent tap, which dictation owns.
    private let allowsStandaloneModifier: Bool
    private let reservedBindings: [ReservedBinding]
    private var pendingStandaloneModifier: HotkeyBinding?
    private var suppressStandaloneModifierUntilRelease = false
    private var captureIsComplete = false

    init(allowsStandaloneModifier: Bool = true, reservedBindings: [ReservedBinding] = []) {
        self.allowsStandaloneModifier = allowsStandaloneModifier
        self.reservedBindings = reservedBindings
    }

    /// Clears the in-flight capture only; the configuration is fixed for the
    /// session's lifetime.
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
            return .rejected(missingModifierMessage)
        }
        if let message = reservedMessage(for: candidate) {
            return .rejected(message)
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

        // Say no on the press, not on the release: a capture that can't take
        // Right Control shouldn't leave the user holding a key that never
        // resolves. The matching release is then swallowed by the suppression.
        guard allowsStandaloneModifier else {
            pendingStandaloneModifier = nil
            suppressStandaloneModifierUntilRelease = true
            return .rejected(Self.standaloneModifierReservedMessage)
        }

        if pendingStandaloneModifier == nil {
            pendingStandaloneModifier = candidate
            return .pendingStandaloneModifier
        }

        guard pendingStandaloneModifier == candidate else { return .ignored }
        pendingStandaloneModifier = nil
        if let message = reservedMessage(for: candidate) {
            return .rejected(message)
        }
        captureIsComplete = true
        return .captured(candidate)
    }

    private func reservedMessage(for candidate: HotkeyBinding) -> String? {
        reservedBindings.first { $0.binding == candidate }?.message
    }

    private var missingModifierMessage: String {
        allowsStandaloneModifier
            ? "Add at least one modifier (⌘ ⌥ ⌃ ⇧), pick a function key, or press Right Control."
            : "Add at least one modifier (⌘ ⌥ ⌃ ⇧) or pick a function key."
    }

    static let standaloneModifierReservedMessage =
        "Right Control is reserved for dictation. Use a key with a modifier (⌘ ⌥ ⌃ ⇧) or a function key."
}
