import Carbon.HIToolbox
import Foundation
import OSLog

final class HotkeyManager {
    typealias Handler = () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = OSType(0x56544C48)
    private let hotKeyId: UInt32 = 1
    private var handler: Handler?
    private(set) var isRegistered = false

    static let shared = HotkeyManager()

    private init() {}

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) {
        unregister()
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, _: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                AppLog.app.info("Hotkey fired")
                manager.handler?()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        guard installStatus == noErr else {
            AppLog.app.error("InstallEventHandler failed with status \(installStatus)")
            return
        }

        var hotKeyId = EventHotKeyID(signature: signature, id: self.hotKeyId)
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

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        handler = nil
        isRegistered = false
    }
}

enum HotkeyDefaults {
    static let optionSpace = (keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
}
