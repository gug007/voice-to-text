import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog

final class HotkeyManager {
    typealias Handler = (DictationHotkeyEvent) -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var localModifierMonitor: Any?
    private var globalModifierMonitor: Any?
    private let signature: OSType = OSType(0x56544C48)
    private let hotKeyId: UInt32 = 1
    private var handler: Handler?
    private var standaloneModifierIsDown = false
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

        let monitor: (NSEvent) -> Void = { [weak self] event in
            self?.handleStandaloneModifierEvent(event)
        }
        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            monitor(event)
            return event
        }
        globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: monitor)
        isRegistered = true
        AppLog.app.info("Standalone modifier hotkey registered: keyCode=\(binding.keyCode)")
    }

    private func handleStandaloneModifierEvent(_ event: NSEvent) {
        guard event.keyCode == UInt16(kVK_RightControl) else { return }

        let isDown = event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
        guard isDown != standaloneModifierIsDown else { return }

        standaloneModifierIsDown = isDown
        if isDown {
            AppLog.app.info("Standalone modifier hotkey pressed")
            handler?(.pressed)
        } else {
            AppLog.app.info("Standalone modifier hotkey released")
            handler?(.released)
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
        if let localModifierMonitor {
            NSEvent.removeMonitor(localModifierMonitor)
            self.localModifierMonitor = nil
        }
        if let globalModifierMonitor {
            NSEvent.removeMonitor(globalModifierMonitor)
            self.globalModifierMonitor = nil
        }
        handler = nil
        standaloneModifierIsDown = false
        isRegistered = false
    }
}
