import AppKit
import Carbon.HIToolbox
import Foundation

enum LaunchContext {
    /// Passed by an app that launches VoiceToText only to use the local API
    /// (`open -g -a VoiceToText --args --background`): the launch stays
    /// headless, like a login-item launch.
    static let backgroundArgument = "--background"

    static func isBackgroundLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.dropFirst().contains(backgroundArgument)
    }

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
