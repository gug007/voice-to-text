import Foundation

struct MicrophoneSelectionHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw MicrophoneSelectionHarnessFailure(description: message)
    }
}

private let airPods = InputDevice(uid: "9C-F3-AC-31-D0-6E:input", name: "Гурген’s AirPods 4", caption: "Bluetooth")
private let builtIn = InputDevice(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone", caption: "Built-in")
private let nb104 = InputDevice(uid: "AppleUSBAudioEngine:NB:NB-104:1:1", name: "NB-104", caption: "USB")

/// The picker's lookup: a UID against the devices in a snapshot.
private func resolveAmong(storedUID: String?, lastKnownName: String?, _ devices: [InputDevice]) -> MicrophoneSelection<InputDevice> {
    MicrophoneSelection.resolve(storedUID: storedUID, lastKnownName: lastKnownName) { uid in
        devices.first { $0.uid == uid }
    }
}

@main
struct MicrophoneSelectionHarness {
    static func main() throws {
        try nothingStoredFollowsTheSystemDefault()
        try blankStoredValuesFollowTheSystemDefault()
        try theDefaultPathNeverLooksAnythingUp()
        try aPinnedPresentDeviceIsUsed()
        try aPinnedMissingDeviceKeepsItsLastKnownName()
        try aPinnedMissingDeviceWithoutANameStillResolves()
        try uidsMatchExactly()
        try storedWhitespaceIsTrimmed()
        try theRecorderPayloadResolvesToALiveID()
        try onlyAPresentPinBindsCapture()
        try preferencesRoundTripThroughUserDefaults()
        try selectingWritesBothKeysAndAnnouncesIt()
        try theMenuBeforeTheFirstEnumerationClaimsNothing()
        try systemDefaultNamesTheCurrentInput()
        try systemDefaultSaysWhenNothingIsConnected()
        try deviceRowsKeepHALOrderWithTransportCaptions()
        try aPinnedPresentDeviceIsSelectedWithoutAnExtraRow()
        try aRenamedPinnedDeviceIsReported()
        try aBlankLiveNameNeverOverwritesTheStoredOne()
        try aPinnedMissingDeviceStaysListedAndSelected()
        try aPinnedMissingDeviceWithoutANameGetsAPlaceholder()
        try aPinBeforeTheFirstEnumerationIsNotCalledDisconnected()
        try duplicateNamesAreNumbered()
        try duplicateUIDsCollapseToOneRow()
        try devicesWithoutAUIDAreNotListed()
        try unnamedDevicesGetAPlaceholderTitle()
        try aMissingPinSharingAPresentDevicesNameStaysDistinct()
        try everyRowHasAUniqueValue()
        print("Microphone selection harness passed")
    }

    // MARK: - Resolution

    private static func nothingStoredFollowsTheSystemDefault() throws {
        let selection = resolveAmong(storedUID: nil, lastKnownName: nil, [airPods, builtIn])
        try expect(selection == .systemDefault, "no stored UID resolves to the system default")
        try expect(selection.pinned == nil, "and binds nothing")
    }

    private static func blankStoredValuesFollowTheSystemDefault() throws {
        for blank in ["", "   ", "\n\t"] {
            let selection = resolveAmong(storedUID: blank, lastKnownName: "NB-104", [airPods])
            try expect(selection == .systemDefault, "a blank stored UID (\(blank.debugDescription)) is the system default, not a pin")
        }
    }

    /// The recorder's start path: nothing pinned must cost no HAL lookup.
    private static func theDefaultPathNeverLooksAnythingUp() throws {
        var lookups = 0
        let selection = MicrophoneSelection<UInt32>.resolve(storedUID: nil, lastKnownName: nil) { _ in
            lookups += 1
            return 70
        }
        try expect(selection == .systemDefault, "nothing stored resolves to the default")
        try expect(lookups == 0, "without consulting the device lookup at all")
        _ = MicrophoneSelection<UInt32>.resolve(storedUID: "", lastKnownName: nil) { _ in
            lookups += 1
            return 70
        }
        try expect(lookups == 0, "an empty string does not consult it either")
    }

    private static func aPinnedPresentDeviceIsUsed() throws {
        let selection = resolveAmong(
            storedUID: builtIn.uid, lastKnownName: builtIn.name, [airPods, builtIn]
        )
        try expect(selection == .pinned(uid: builtIn.uid, device: builtIn), "a connected pin resolves to that device")
    }

    private static func aPinnedMissingDeviceKeepsItsLastKnownName() throws {
        let selection = resolveAmong(storedUID: nb104.uid, lastKnownName: "NB-104", [airPods, builtIn])
        try expect(selection == .missing(uid: nb104.uid, lastKnownName: "NB-104"), "an unplugged pin is missing, named as last seen")
    }

    private static func aPinnedMissingDeviceWithoutANameStillResolves() throws {
        for name in [nil, "", "  "] as [String?] {
            let selection = resolveAmong(storedUID: nb104.uid, lastKnownName: name, [builtIn])
            try expect(selection == .missing(uid: nb104.uid, lastKnownName: nil), "a missing pin with no usable name (\(String(describing: name))) has no name")
        }
    }

    private static func uidsMatchExactly() throws {
        let selection = resolveAmong(storedUID: "builtinmicrophonedevice", lastKnownName: nil, [builtIn])
        try expect(
            selection == .missing(uid: "builtinmicrophonedevice", lastKnownName: nil),
            "UIDs are identities, compared exactly — not case-folded into a different device"
        )
    }

    private static func storedWhitespaceIsTrimmed() throws {
        let selection = resolveAmong(storedUID: "  \(builtIn.uid)\n", lastKnownName: nil, [builtIn])
        try expect(selection == .pinned(uid: builtIn.uid, device: builtIn), "a hand-edited UID with stray whitespace still matches")
    }

    private static func theRecorderPayloadResolvesToALiveID() throws {
        var asked: [String] = []
        let selection = MicrophoneSelection<UInt32>.resolve(storedUID: airPods.uid, lastKnownName: nil) { uid in
            asked.append(uid)
            return uid == airPods.uid ? 88 : nil
        }
        try expect(selection == .pinned(uid: airPods.uid, device: 88), "the recorder resolves a pin to the live device id")
        try expect(asked == [airPods.uid], "with exactly one lookup, for the stored UID")
    }

    private static func onlyAPresentPinBindsCapture() throws {
        try expect(
            MicrophoneSelection<UInt32>.pinned(uid: "a", device: 1).pinned.map { "\($0.uid)/\($0.device)" } == "a/1",
            "a connected pin hands its UID to capture"
        )
        try expect(
            MicrophoneSelection<UInt32>.missing(uid: "a", lastKnownName: "A").pinned == nil,
            "a missing pin falls back to the system default instead of failing the take"
        )
        try expect(MicrophoneSelection<UInt32>.systemDefault.pinned == nil, "the default binds nothing")
    }

    private static func preferencesRoundTripThroughUserDefaults() throws {
        let suite = "MicrophoneSelectionHarness.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw MicrophoneSelectionHarnessFailure(description: "could not open a scratch defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        try expect(
            MicrophonePreference.stored(in: defaults) == .init(uid: nil, lastKnownName: nil),
            "a fresh install stores nothing"
        )
        defaults.set("", forKey: MicrophonePreference.uidKey)
        defaults.set(" ", forKey: MicrophonePreference.nameKey)
        try expect(
            MicrophonePreference.stored(in: defaults) == .init(uid: nil, lastKnownName: nil),
            "blank values read back as nothing stored"
        )
        defaults.set(airPods.uid, forKey: MicrophonePreference.uidKey)
        defaults.set(airPods.name, forKey: MicrophonePreference.nameKey)
        try expect(
            MicrophonePreference.stored(in: defaults) == .init(uid: airPods.uid, lastKnownName: airPods.name),
            "a pin and its non-ASCII name read back unchanged"
        )
    }

    private static func selectingWritesBothKeysAndAnnouncesIt() throws {
        let suite = "MicrophoneSelectionHarness.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw MicrophoneSelectionHarnessFailure(description: "could not open a scratch defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        var posts = 0
        let observer = NotificationCenter.default.addObserver(
            forName: MicrophonePreference.didChangeNotification, object: nil, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        MicrophonePreference.select(airPods, in: defaults)
        try expect(
            MicrophonePreference.stored(in: defaults) == .init(uid: airPods.uid, lastKnownName: airPods.name),
            "pinning stores the UID and the name together"
        )
        try expect(posts == 1, "and tells the recorders")

        MicrophonePreference.select(InputDevice(uid: nb104.uid, name: "  ", caption: nil), in: defaults)
        try expect(
            MicrophonePreference.stored(in: defaults) == .init(uid: nb104.uid, lastKnownName: nil),
            "a blank name is not stored over the previous device's"
        )

        MicrophonePreference.recordName("NB-104 (desk)", in: defaults)
        try expect(MicrophonePreference.stored(in: defaults).lastKnownName == "NB-104 (desk)", "a rename refreshes the stored name")
        try expect(posts == 2, "without announcing a change of microphone")

        MicrophonePreference.select(nil, in: defaults)
        try expect(
            MicrophonePreference.stored(in: defaults) == .init(uid: nil, lastKnownName: nil),
            "the system default clears both keys"
        )
        try expect(posts == 3, "and is announced too")
    }

    // MARK: - Picker model

    private static func theMenuBeforeTheFirstEnumerationClaimsNothing() throws {
        let menu = MicrophoneMenu(storedUID: nil, lastKnownName: nil, snapshot: nil)
        try expect(menu.systemDefault.value == nil, "the lead row is the system default")
        try expect(menu.systemDefault.title == "System default", "titled as such")
        try expect(menu.systemDefault.detail == nil, "with no claim about the current input before anything is read")
        try expect(menu.devices.isEmpty, "and no device rows yet")
        try expect(menu.selection == nil, "selecting the default")
        try expect(menu.subtitle == MicrophoneMenu.defaultSubtitle, "the subtitle says what the setting covers")
        try expect(menu.subtitle.contains("dictation") && menu.subtitle.contains("conversations"), "both dictation and conversations")
    }

    private static func systemDefaultNamesTheCurrentInput() throws {
        let menu = MicrophoneMenu(
            storedUID: nil, lastKnownName: nil,
            snapshot: InputDeviceSnapshot(devices: [airPods, builtIn], defaultInputName: airPods.name)
        )
        try expect(menu.systemDefault.detail == "Currently Гурген’s AirPods 4", "the default row names the live default, non-ASCII intact")
    }

    private static func systemDefaultSaysWhenNothingIsConnected() throws {
        for name in [nil, ""] as [String?] {
            let menu = MicrophoneMenu(storedUID: nil, lastKnownName: nil, snapshot: InputDeviceSnapshot(devices: [], defaultInputName: name))
            try expect(menu.systemDefault.detail == "No microphone connected", "an enumerated Mac with no default input says so")
            try expect(menu.devices.isEmpty, "and lists nothing")
        }
    }

    private static func deviceRowsKeepHALOrderWithTransportCaptions() throws {
        let odd = InputDevice(uid: "odd", name: "Odd Box", caption: nil)
        let menu = MicrophoneMenu(
            storedUID: nil, lastKnownName: nil,
            snapshot: InputDeviceSnapshot(devices: [nb104, builtIn, airPods, odd], defaultInputName: nil)
        )
        try expect(menu.devices.map(\.title) == ["NB-104", "MacBook Pro Microphone", "Гурген’s AirPods 4", "Odd Box"], "rows keep the HAL's order")
        try expect(menu.devices.map(\.value) == [nb104.uid, builtIn.uid, airPods.uid, "odd"], "each row's value is its UID")
        try expect(menu.devices.map(\.caption) == ["USB", "Built-in", "Bluetooth", nil], "captions are the transport, none when unknown")
        try expect(menu.devices.allSatisfy { $0.detail == nil }, "a connected device needs no detail line")
    }

    private static func aPinnedPresentDeviceIsSelectedWithoutAnExtraRow() throws {
        let menu = MicrophoneMenu(
            storedUID: builtIn.uid, lastKnownName: builtIn.name,
            snapshot: InputDeviceSnapshot(devices: [airPods, builtIn], defaultInputName: airPods.name)
        )
        try expect(menu.selection == builtIn.uid, "the pinned device is checked")
        try expect(menu.devices.count == 2, "without a duplicate row for it")
        try expect(menu.subtitle == MicrophoneMenu.defaultSubtitle, "and the subtitle raises nothing")
        try expect(menu.renamedPinnedDevice == nil, "an unchanged name needs no refresh")
    }

    private static func aRenamedPinnedDeviceIsReported() throws {
        let renamed = InputDevice(uid: airPods.uid, name: "Work AirPods", caption: "Bluetooth")
        let snapshot = InputDeviceSnapshot(devices: [renamed], defaultInputName: nil)
        let menu = MicrophoneMenu(storedUID: airPods.uid, lastKnownName: airPods.name, snapshot: snapshot)
        try expect(menu.renamedPinnedDevice == "Work AirPods", "a renamed pin reports its new name for the stored copy")
        let unnamed = MicrophoneMenu(storedUID: airPods.uid, lastKnownName: nil, snapshot: snapshot)
        try expect(unnamed.renamedPinnedDevice == "Work AirPods", "a pin stored without a name gets one the first time it is seen")
    }

    private static func aBlankLiveNameNeverOverwritesTheStoredOne() throws {
        let blank = InputDevice(uid: nb104.uid, name: "  ", caption: "USB")
        let menu = MicrophoneMenu(
            storedUID: nb104.uid, lastKnownName: "NB-104",
            snapshot: InputDeviceSnapshot(devices: [blank], defaultInputName: nil)
        )
        try expect(menu.renamedPinnedDevice == nil, "a device momentarily reporting no name keeps the stored one")
    }

    private static func aPinnedMissingDeviceStaysListedAndSelected() throws {
        let menu = MicrophoneMenu(
            storedUID: nb104.uid, lastKnownName: "NB-104",
            snapshot: InputDeviceSnapshot(devices: [airPods, builtIn], defaultInputName: airPods.name)
        )
        try expect(menu.selection == nb104.uid, "the unplugged pin stays selected rather than resetting")
        try expect(menu.devices.count == 3, "and stays listed")
        try expect(menu.devices.last == .init(
            value: nb104.uid, title: "NB-104", detail: "Not connected — using system default", caption: nil
        ), "last, after everything usable, saying what is happening")
        try expect(
            menu.subtitle == "NB-104 isn’t connected, so dictation and conversations use the system default.",
            "the card's subtitle says so too, since the collapsed control shows only the title"
        )
        try expect(menu.renamedPinnedDevice == nil, "a missing device has no live name to persist")
    }

    private static func aPinnedMissingDeviceWithoutANameGetsAPlaceholder() throws {
        let menu = MicrophoneMenu(
            storedUID: nb104.uid, lastKnownName: nil,
            snapshot: InputDeviceSnapshot(devices: [builtIn], defaultInputName: builtIn.name)
        )
        try expect(menu.devices.last?.title == "Previously selected microphone", "a nameless missing pin still gets a readable title")
        try expect(menu.devices.last?.value == nb104.uid, "keyed by its UID")
        try expect(menu.subtitle.hasPrefix("The selected microphone isn’t connected"), "and a subtitle that doesn't print a UID")
    }

    private static func aPinBeforeTheFirstEnumerationIsNotCalledDisconnected() throws {
        let menu = MicrophoneMenu(storedUID: airPods.uid, lastKnownName: airPods.name, snapshot: nil)
        try expect(menu.selection == airPods.uid, "the pin is selected from the first frame")
        try expect(menu.devices == [.init(value: airPods.uid, title: airPods.name, detail: nil, caption: nil)], "listed under its stored name")
        try expect(menu.subtitle == MicrophoneMenu.defaultSubtitle, "and not announced as disconnected before anything was read")
    }

    private static func duplicateNamesAreNumbered() throws {
        let first = InputDevice(uid: "usb-a", name: "USB Audio Device", caption: "USB")
        let second = InputDevice(uid: "usb-b", name: "USB Audio Device", caption: "USB")
        let third = InputDevice(uid: "usb-c", name: "USB Audio Device", caption: "USB")
        let menu = MicrophoneMenu(
            storedUID: "usb-b", lastKnownName: "USB Audio Device",
            snapshot: InputDeviceSnapshot(devices: [first, builtIn, second, third], defaultInputName: nil)
        )
        try expect(
            menu.devices.map(\.title) == ["USB Audio Device", "MacBook Pro Microphone", "USB Audio Device (2)", "USB Audio Device (3)"],
            "repeats of one name are numbered in order; unique names are untouched"
        )
        try expect(menu.selection == "usb-b", "the selection follows the UID, not the title")
        try expect(menu.renamedPinnedDevice == nil, "the numbering is presentation only and is never persisted as a rename")
    }

    private static func duplicateUIDsCollapseToOneRow() throws {
        let echo = InputDevice(uid: builtIn.uid, name: "Echo", caption: "Built-in")
        let menu = MicrophoneMenu(
            storedUID: nil, lastKnownName: nil,
            snapshot: InputDeviceSnapshot(devices: [builtIn, echo], defaultInputName: nil)
        )
        try expect(menu.devices.map(\.title) == ["MacBook Pro Microphone"], "a UID reported twice keeps its first row only")
    }

    private static func devicesWithoutAUIDAreNotListed() throws {
        let noUID = InputDevice(uid: " ", name: "Ghost", caption: "Virtual")
        let menu = MicrophoneMenu(
            storedUID: nil, lastKnownName: nil,
            snapshot: InputDeviceSnapshot(devices: [noUID, builtIn], defaultInputName: nil)
        )
        try expect(menu.devices.map(\.value) == [builtIn.uid], "a device that cannot be pinned is not offered")
    }

    private static func unnamedDevicesGetAPlaceholderTitle() throws {
        let a = InputDevice(uid: "a", name: "", caption: "USB")
        let b = InputDevice(uid: "b", name: " ", caption: "USB")
        let menu = MicrophoneMenu(storedUID: nil, lastKnownName: nil, snapshot: InputDeviceSnapshot(devices: [a, b], defaultInputName: nil))
        try expect(menu.devices.map(\.title) == ["Unnamed microphone", "Unnamed microphone (2)"], "nameless devices are titled and told apart")
    }

    /// Two units of one model: the pinned one is away, its twin is plugged in.
    private static func aMissingPinSharingAPresentDevicesNameStaysDistinct() throws {
        let twin = InputDevice(uid: "AppleUSBAudioEngine:NB:NB-104:2:1", name: "NB-104", caption: "USB")
        let menu = MicrophoneMenu(
            storedUID: nb104.uid, lastKnownName: "NB-104",
            snapshot: InputDeviceSnapshot(devices: [twin], defaultInputName: twin.name)
        )
        try expect(menu.devices.map(\.value) == [twin.uid, nb104.uid], "both are listed, keyed by their own UIDs")
        try expect(menu.devices.map(\.detail) == [nil, MicrophoneMenu.disconnectedDetail], "and the detail line tells them apart")
        try expect(menu.selection == nb104.uid, "the pin is still the absent unit, not the twin with its name")
    }

    private static func everyRowHasAUniqueValue() throws {
        let snapshot = InputDeviceSnapshot(
            devices: [airPods, builtIn, nb104, InputDevice(uid: airPods.uid, name: "dup", caption: "Bluetooth")],
            defaultInputName: airPods.name
        )
        for stored in [nil, airPods.uid, "gone"] as [String?] {
            let menu = MicrophoneMenu(storedUID: stored, lastKnownName: "Gone Mic", snapshot: snapshot)
            let values = [menu.systemDefault.value] + menu.devices.map(\.value)
            try expect(Set(values).count == values.count, "the dropdown keys rows by value, so none may repeat (stored: \(String(describing: stored)))")
            try expect(values.contains(menu.selection), "and the selection is always one of them")
        }
    }
}
