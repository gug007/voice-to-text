import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog

final class HotkeyManager {
    typealias Handler = (DictationHotkeyEvent) -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var modifierEventTap: CFMachPort?
    private var modifierRunLoopSource: CFRunLoopSource?
    private let signature: OSType = OSType(0x56544C48)
    private let hotKeyId: UInt32 = 1
    private var handler: Handler?
    private var standaloneModifierState = StandaloneModifierHotkeyState(
        modifierKeyCode: UInt16(kVK_RightControl)
    )
    private var standaloneModifierPressWorkItem: DispatchWorkItem?
    private(set) var isRegistered = false

    static let shared = HotkeyManager()

    private init() {}

    func register(binding: HotkeyBinding, handler: @escaping Handler) {
        unregister()
        self.handler = handler

        if binding.isStandaloneModifier {
            registerStandaloneModifier(binding: binding)
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

    private func registerStandaloneModifier(binding: HotkeyBinding) {
        guard binding == .rightControlBinding else { return }

        guard ListenEventPermission.isGranted || ListenEventPermission.request() else {
            AppLog.app.error("Standalone modifier hotkey needs Input Monitoring permission")
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userData in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                DispatchQueue.main.async {
                    manager.handleStandaloneModifierEvent(type: type, keyCode: keyCode)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
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

    private func handleStandaloneModifierEvent(type: CGEventType, keyCode: UInt16) {
        let effects: [StandaloneModifierHotkeyEffect]
        switch type {
        case .flagsChanged:
            effects = standaloneModifierState.handleFlagsChanged(keyCode: keyCode)
        case .keyDown:
            effects = standaloneModifierState.handleKeyDown(keyCode: keyCode)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            AppLog.app.warning("Standalone modifier event tap was disabled; re-enabling")
            if let modifierEventTap {
                CGEvent.tapEnable(tap: modifierEventTap, enable: true)
                isRegistered = true
            }
            effects = []
        default:
            effects = []
        }
        applyStandaloneModifierEffects(effects)
    }

    private func applyStandaloneModifierEffects(_ effects: [StandaloneModifierHotkeyEffect]) {
        for effect in effects {
            switch effect {
            case .schedulePress(let token):
                standaloneModifierPressWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    let delayedEffects = self.standaloneModifierState.fireScheduledPress(token: token)
                    self.applyStandaloneModifierEffects(delayedEffects)
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
        applyStandaloneModifierEffects(standaloneModifierState.reset())
        handler = nil
        isRegistered = false
    }
}
