import AppKit
import Carbon.HIToolbox
import Foundation

enum LaunchContext {
    static func shouldHideMainWindowOnLaunch(
        appleEvent: NSAppleEventDescriptor?,
        launchUserInfo: [AnyHashable: Any]? = nil
    ) -> Bool {
        if let isLoginItemLaunch = loginItemLaunchFlag(appleEvent: appleEvent) {
            return isLoginItemLaunch
        }
        if let isDefaultLaunch = launchUserInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool {
            return !isDefaultLaunch
        }
        return false
    }

    private static func loginItemLaunchFlag(appleEvent: NSAppleEventDescriptor?) -> Bool? {
        guard let appleEvent,
              appleEvent.eventID == kAEOpenApplication else {
            return nil
        }
        guard let descriptor = appleEvent.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) else {
            return nil
        }
        return descriptor.descriptorType == typeBoolean ? descriptor.booleanValue : true
    }
}
