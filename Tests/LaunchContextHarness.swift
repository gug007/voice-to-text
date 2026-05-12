import AppKit
import Carbon.HIToolbox
import Foundation

struct HarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(
    _ actual: Bool,
    _ expected: Bool,
    _ message: String
) throws {
    if actual != expected {
        throw HarnessFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

private func openApplicationEvent(loginItem: Bool) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(
        eventClass: AEEventClass(kCoreEventClass),
        eventID: AEEventID(kAEOpenApplication),
        targetDescriptor: nil,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
    if loginItem {
        event.setParam(
            NSAppleEventDescriptor(typeCode: OSType(keyAELaunchedAsLogInItem)),
            forKeyword: keyAEPropData
        )
    }
    return event
}

@main
struct LaunchContextHarness {
    static func main() throws {
        try expect(
            LaunchContext.shouldHideMainWindowOnLaunch(
                launchIsDefault: false,
                appleEvent: openApplicationEvent(loginItem: false)
            ),
            false,
            "manual non-default launches stay interactive"
        )
        try expect(
            LaunchContext.shouldHideMainWindowOnLaunch(
                launchIsDefault: nil,
                appleEvent: openApplicationEvent(loginItem: true)
            ),
            true,
            "login-item launches start hidden"
        )
        try expect(
            LaunchContext.shouldHideMainWindowOnLaunch(
                launchIsDefault: true,
                appleEvent: nil
            ),
            false,
            "default launches stay visible"
        )

        print("Launch context harness passed")
    }
}
