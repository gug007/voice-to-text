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

final class HotkeyManager {
    typealias Handler = (DictationHotkeyEvent) -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var modifierEventTap: CFMachPort?
    private var modifierRunLoopSource: CFRunLoopSource?
    private var modifierEventTapContext: StandaloneModifierEventTapContext?
    private let signature: OSType = OSType(0x56544C48)
    private let hotKeyId: UInt32 = 1
    private var handler: Handler?
    private var registrationGeneration: UInt64 = 0
    private var standaloneModifierState = StandaloneModifierHotkeyState(
        modifierKeyCode: UInt16(kVK_RightControl)
    )
    private var standaloneActiveInputTracker = StandaloneActiveInputTracker()
    private var standaloneModifierPressWorkItem: DispatchWorkItem?
    private(set) var isRegistered = false
    private let rightControlDeviceMask = UInt64(NX_DEVICERCTLKEYMASK)
    private let nonControlModifierDeviceMask = UInt64(
        NX_DEVICELSHIFTKEYMASK
            | NX_DEVICERSHIFTKEYMASK
            | NX_DEVICELCMDKEYMASK
            | NX_DEVICERCMDKEYMASK
            | NX_DEVICELALTKEYMASK
            | NX_DEVICERALTKEYMASK
    )

    static let shared = HotkeyManager()

    private init() {}

    func register(binding: HotkeyBinding, handler: @escaping Handler) {
        unregister()
        registrationGeneration &+= 1
        self.handler = handler

        if binding.isStandaloneModifier {
            registerStandaloneModifier(binding: binding, generation: registrationGeneration)
        } else {
            registerCarbonHotkey(
                keyCode: binding.keyCode,
                modifiers: binding.modifiers
            )
        }
    }

    private func registerCarbonHotkey(keyCode: UInt32, modifiers: UInt32) {
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
            return
        }

        let hotKeyId = EventHotKeyID(signature: signature, id: self.hotKeyId)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            isRegistered = true
            AppLog.app.info("Hotkey registered: keyCode=\(keyCode) modifiers=\(modifiers)")
        } else {
            AppLog.app.error("RegisterEventHotKey failed with status \(registerStatus)")
        }
    }

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
                let hasOtherModifierDown = event.flags.rawValue & manager.nonControlModifierDeviceMask != 0
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

    private func handleCarbonEvent(_ event: EventRef) {
        let eventKind = GetEventKind(event)
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
    }

    func unregister() {
        let generation = registrationGeneration
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
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
        isRegistered = false
    }
}
