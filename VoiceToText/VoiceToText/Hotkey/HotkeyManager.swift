import AppKit
import Carbon.HIToolbox
import Foundation
import IOKit.hidsystem
import OSLog

private final class StandaloneModifierEventTapContext {
    weak var manager: HotkeyManager?
    let generation: UInt64

    init(manager: HotkeyManager, generation: UInt64) {
        self.manager = manager
        self.generation = generation
    }
}

/// Which global shortcut a Carbon registration belongs to. The raw value is the
/// `EventHotKeyID.id` the OS hands back when a hotkey fires, so the shared
/// Carbon event handler can tell the two apart.
nonisolated enum HotkeySlot: UInt32 {
    case dictation = 1
    case meeting = 2
}

final class HotkeyManager {
    typealias Handler = (DictationHotkeyEvent) -> Void

    private var carbonHotKeyRefs: [HotkeySlot: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var modifierEventTap: CFMachPort?
    private var modifierRunLoopSource: CFRunLoopSource?
    private var modifierEventTapContext: StandaloneModifierEventTapContext?
    private let signature: OSType = OSType(0x56544C48)
    private var handler: Handler?
    private var meetingHandler: (() -> Void)?
    /// The dictation binding as last registered, so the meeting slot can refuse
    /// a colliding binding without reaching into the store.
    private var dictationBinding: HotkeyBinding?
    private var registrationGeneration: UInt64 = 0
    private var standaloneModifierState = StandaloneModifierHotkeyState(
        modifierKeyCode: UInt16(kVK_RightControl)
    )
    private var standaloneActiveInputTracker = StandaloneActiveInputTracker()
    private var standaloneModifierPressWorkItem: DispatchWorkItem?
    private(set) var isRegistered = false
    private(set) var isMeetingRegistered = false
    private let rightControlDeviceMask = UInt64(NX_DEVICERCTLKEYMASK)
    private let otherModifierDeviceMask = UInt64(
        NX_DEVICELCTLKEYMASK
            | NX_DEVICELSHIFTKEYMASK
            | NX_DEVICERSHIFTKEYMASK
            | NX_DEVICELCMDKEYMASK
            | NX_DEVICERCMDKEYMASK
            | NX_DEVICELALTKEYMASK
            | NX_DEVICERALTKEYMASK
    )

    static let shared = HotkeyManager()

    private init() {}

    /// Liveness, not just "did we register once": the standalone-modifier event
    /// tap can be invalidated by the OS without delivering a `.tapDisabled*`
    /// event, leaving `isRegistered` stuck true over a dead port. The Carbon
    /// hotkey can't die this way, so a nil tap with `isRegistered` reads healthy.
    var isHealthy: Bool {
        guard isRegistered else { return false }
        guard let modifierEventTap else { return true }
        return CFMachPortIsValid(modifierEventTap) && CGEvent.tapIsEnabled(tap: modifierEventTap)
    }

    // MARK: - Dictation slot

    func register(binding: HotkeyBinding, handler: @escaping Handler) {
        unregister()
        registrationGeneration &+= 1
        self.handler = handler
        dictationBinding = binding

        if binding.isStandaloneModifier {
            registerStandaloneModifier(binding: binding, generation: registrationGeneration)
        } else if registerCarbonHotkey(
            slot: .dictation,
            keyCode: binding.keyCode,
            modifiers: binding.modifiers
        ) {
            isRegistered = true
            AppLog.app.info("Hotkey registered: keyCode=\(binding.keyCode) modifiers=\(binding.modifiers)")
        }
    }

    func unregister() {
        let generation = registrationGeneration
        unregisterCarbonHotkey(slot: .dictation)
        if let modifierRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), modifierRunLoopSource, .commonModes)
            self.modifierRunLoopSource = nil
        }
        if let modifierEventTap {
            CFMachPortInvalidate(modifierEventTap)
            self.modifierEventTap = nil
        }
        modifierEventTapContext = nil
        standaloneActiveInputTracker.reset()
        applyStandaloneModifierEffects(standaloneModifierState.reset(), generation: generation)
        standaloneModifierPressWorkItem?.cancel()
        standaloneModifierPressWorkItem = nil
        registrationGeneration &+= 1
        handler = nil
        dictationBinding = nil
        isRegistered = false
    }

    // MARK: - Meeting slot

    /// Registers the conversation shortcut. Carbon-only by design: the
    /// standalone-modifier path owns a process-wide CGEvent tap and a single
    /// press/release state machine, both of which belong to dictation.
    func registerMeeting(binding: HotkeyBinding, handler: @escaping () -> Void) {
        unregisterMeeting()

        guard !binding.isStandaloneModifier else {
            AppLog.app.error("Conversation hotkey can't be a standalone modifier; Right Control is reserved for dictation")
            return
        }
        guard binding != dictationBinding else {
            AppLog.app.error("Conversation hotkey matches the dictation hotkey; refusing to register it")
            return
        }
        guard registerCarbonHotkey(
            slot: .meeting,
            keyCode: binding.keyCode,
            modifiers: binding.modifiers
        ) else { return }

        meetingHandler = handler
        isMeetingRegistered = true
        AppLog.app.info("Conversation hotkey registered: keyCode=\(binding.keyCode) modifiers=\(binding.modifiers)")
    }

    func unregisterMeeting() {
        unregisterCarbonHotkey(slot: .meeting)
        meetingHandler = nil
        isMeetingRegistered = false
    }

    // MARK: - Carbon plumbing

    private func registerCarbonHotkey(slot: HotkeySlot, keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard installCarbonEventHandlerIfNeeded() else { return false }

        var ref: EventHotKeyRef?
        let hotKeyId = EventHotKeyID(signature: signature, id: slot.rawValue)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard registerStatus == noErr, let ref else {
            AppLog.app.error("RegisterEventHotKey failed with status \(registerStatus)")
            return false
        }
        carbonHotKeyRefs[slot] = ref
        return true
    }

    private func unregisterCarbonHotkey(slot: HotkeySlot) {
        guard let ref = carbonHotKeyRefs.removeValue(forKey: slot) else { return }
        UnregisterEventHotKey(ref)
    }

    /// Installed once and kept for the app's lifetime. Both slots are delivered
    /// through this one handler, so tearing it down when either unregisters
    /// would silently deafen the other.
    private func installCarbonEventHandlerIfNeeded() -> Bool {
        guard eventHandler == nil else { return true }

        let eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                { (_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
                    guard let userData, let event else { return noErr }
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                    manager.handleCarbonEvent(event)
                    return noErr
                },
                buffer.count,
                buffer.baseAddress,
                selfPtr,
                &eventHandler
            )
        }

        guard installStatus == noErr else {
            AppLog.app.error("InstallEventHandler failed with status \(installStatus)")
            eventHandler = nil
            return false
        }
        return true
    }

    private func handleCarbonEvent(_ event: EventRef) {
        // With two hotkeys sharing one handler, the fired id is the only thing
        // that says which shortcut the user pressed.
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == signature,
              let slot = HotkeySlot(rawValue: hotKeyID.id) else { return }

        let eventKind = GetEventKind(event)
        switch slot {
        case .dictation:
            switch eventKind {
            case UInt32(kEventHotKeyPressed):
                AppLog.app.info("Hotkey pressed")
                handler?(.pressed)
            case UInt32(kEventHotKeyReleased):
                AppLog.app.info("Hotkey released")
                handler?(.released)
            default:
                break
            }
        case .meeting:
            // Press-only: conversations have no hold mode, so a release is noise.
            guard eventKind == UInt32(kEventHotKeyPressed) else { return }
            AppLog.app.info("Conversation hotkey pressed")
            meetingHandler?()
        }
    }

    // MARK: - Standalone modifier (dictation only)

    private func registerStandaloneModifier(binding: HotkeyBinding, generation: UInt64) {
        guard binding == .rightControlBinding else { return }

        guard ListenEventPermission.isGranted || ListenEventPermission.request() else {
            AppLog.app.error("Standalone modifier hotkey needs Input Monitoring permission")
            return
        }

        let context = StandaloneModifierEventTapContext(manager: self, generation: generation)
        modifierEventTapContext = context
        let contextPtr = Unmanaged.passUnretained(context).toOpaque()
        let keyboardMask =
            eventMask(for: .flagsChanged)
            | eventMask(for: .keyDown)
            | eventMask(for: .keyUp)
        let mouseMask =
            eventMask(for: .leftMouseDown)
            | eventMask(for: .leftMouseUp)
            | eventMask(for: .rightMouseDown)
            | eventMask(for: .rightMouseUp)
            | eventMask(for: .otherMouseDown)
            | eventMask(for: .otherMouseUp)
        let mask = keyboardMask | mouseMask
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userData in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<StandaloneModifierEventTapContext>.fromOpaque(userData).takeUnretainedValue()
                guard let manager = context.manager else { return Unmanaged.passUnretained(event) }
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let rawMouseButtonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
                let rightControlIsDown = event.flags.rawValue & manager.rightControlDeviceMask != 0
                let hasOtherModifierDown = event.flags.rawValue & manager.otherModifierDeviceMask != 0
                DispatchQueue.main.async {
                    manager.handleStandaloneModifierEvent(
                        type: type,
                        keyCode: keyCode,
                        rawMouseButtonNumber: rawMouseButtonNumber,
                        rightControlIsDown: rightControlIsDown,
                        hasOtherModifierDown: hasOtherModifierDown,
                        generation: context.generation
                    )
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: contextPtr
        ) else {
            modifierEventTapContext = nil
            AppLog.app.error("CGEvent tap creation failed for standalone modifier hotkey")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        modifierEventTap = tap
        modifierRunLoopSource = source
        isRegistered = true
        AppLog.app.info("Standalone modifier hotkey registered: keyCode=\(binding.keyCode)")
    }

    private func handleStandaloneModifierEvent(
        type: CGEventType,
        keyCode: UInt16,
        rawMouseButtonNumber: Int64,
        rightControlIsDown: Bool,
        hasOtherModifierDown: Bool,
        generation: UInt64
    ) {
        guard isCurrentRegistration(generation) else { return }

        let effects: [StandaloneModifierHotkeyEffect]
        switch type {
        case .flagsChanged:
            effects = standaloneModifierState.handleFlagsChanged(
                keyCode: keyCode,
                isModifierDown: rightControlIsDown,
                hasOtherModifierDown: hasOtherModifierDown
                    || standaloneActiveInputTracker.hasActiveInput
                    || NSEvent.pressedMouseButtons != 0
            )
        case .keyDown:
            standaloneActiveInputTracker.keyDown(keyCode, excluding: UInt16(kVK_RightControl))
            effects = standaloneModifierState.handleKeyDown(keyCode: keyCode)
        case .keyUp:
            standaloneActiveInputTracker.keyUp(keyCode)
            effects = []
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            standaloneActiveInputTracker.mouseDown(
                button: normalizedMouseButton(type: type, rawValue: rawMouseButtonNumber)
            )
            effects = standaloneModifierState.handleChord()
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            standaloneActiveInputTracker.mouseUp(
                button: normalizedMouseButton(type: type, rawValue: rawMouseButtonNumber)
            )
            effects = []
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            AppLog.app.warning("Standalone modifier event tap was disabled; re-enabling")
            if let modifierEventTap {
                CGEvent.tapEnable(tap: modifierEventTap, enable: true)
                isRegistered = true
            }
            standaloneActiveInputTracker.reset()
            effects = standaloneModifierState.reset()
        default:
            effects = []
        }
        applyStandaloneModifierEffects(effects, generation: generation)
    }

    private func eventMask(for eventType: CGEventType) -> CGEventMask {
        CGEventMask(1) << eventType.rawValue
    }

    private func normalizedMouseButton(type: CGEventType, rawValue: Int64) -> Int64 {
        switch type {
        case .leftMouseDown, .leftMouseUp:
            return Int64(CGMouseButton.left.rawValue)
        case .rightMouseDown, .rightMouseUp:
            return Int64(CGMouseButton.right.rawValue)
        default:
            return rawValue
        }
    }

    private func applyStandaloneModifierEffects(
        _ effects: [StandaloneModifierHotkeyEffect],
        generation: UInt64
    ) {
        guard isCurrentRegistration(generation) else { return }

        for effect in effects {
            switch effect {
            case .schedulePress(let token):
                standaloneModifierPressWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self, self.isCurrentRegistration(generation) else { return }
                    let delayedEffects = self.standaloneModifierState.fireScheduledPress(token: token)
                    self.applyStandaloneModifierEffects(delayedEffects, generation: generation)
                }
                standaloneModifierPressWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: workItem)

            case .cancelScheduledPress:
                standaloneModifierPressWorkItem?.cancel()
                standaloneModifierPressWorkItem = nil

            case .emitPressed:
                AppLog.app.info("Standalone modifier hotkey pressed")
                handler?(.standalonePressed)

            case .emitReleased:
                AppLog.app.info("Standalone modifier hotkey released")
                handler?(.standaloneReleased)

            case .emitCancelled:
                AppLog.app.info("Standalone modifier hotkey cancelled")
                handler?(.cancel)
            }
        }
    }

    private func isCurrentRegistration(_ generation: UInt64) -> Bool {
        isRegistered && registrationGeneration == generation
    }
}
