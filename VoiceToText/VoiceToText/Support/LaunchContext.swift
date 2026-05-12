import AppKit
import Carbon.HIToolbox
import Foundation

enum LaunchContext {
    static func shouldHideMainWindowOnLaunch(
        launchIsDefault _: Bool?,
        appleEvent: NSAppleEventDescriptor?
    ) -> Bool {
        isLoginItemLaunch(appleEvent: appleEvent)
    }

    private static func isLoginItemLaunch(appleEvent: NSAppleEventDescriptor?) -> Bool {
        guard let appleEvent,
              appleEvent.eventID == kAEOpenApplication,
              let launchDescriptor = appleEvent.paramDescriptor(forKeyword: keyAEPropData) else {
            return false
        }
        return launchDescriptor.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
