import Foundation

struct StandaloneModifierEventCoordinatorHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(
    _ actual: [DictationHotkeyEvent],
    _ expected: [DictationHotkeyEvent],
    _ message: String
) throws {
    if actual != expected {
        throw StandaloneModifierEventCoordinatorHarnessFailure(
            description: "\(message): expected \(expected), got \(actual)"
        )
    }
}

@main
struct StandaloneModifierEventCoordinatorHarness {
    static func main() throws {
        try toggleRecordingDefersStopUntilCleanRelease()
        try toggleRecordingChordCancelsDeferredStop()
        try holdModePreservesPressRelease()
        print("Standalone modifier event coordinator harness passed")
    }

    private static func toggleRecordingDefersStopUntilCleanRelease() throws {
        var coordinator = StandaloneModifierEventCoordinator()
        try expect(
            coordinator.normalize(event: .standalonePressed, mode: .toggle, state: .recording),
            [],
            "toggle recording does not stop on standalone press"
        )
        try expect(
            coordinator.normalize(event: .standaloneReleased, mode: .toggle, state: .recording),
            [.pressed],
            "toggle recording stops on clean standalone release"
        )
    }

    private static func toggleRecordingChordCancelsDeferredStop() throws {
        var coordinator = StandaloneModifierEventCoordinator()
        _ = coordinator.normalize(event: .standalonePressed, mode: .toggle, state: .recording)
        try expect(
            coordinator.normalize(event: .cancel, mode: .toggle, state: .recording),
            [],
            "chord after delayed standalone press cancels deferred toggle stop"
        )
        try expect(
            coordinator.normalize(event: .standaloneReleased, mode: .toggle, state: .recording),
            [],
            "release after cancelled chord does not stop recording"
        )
    }

    private static func holdModePreservesPressRelease() throws {
        var coordinator = StandaloneModifierEventCoordinator()
        try expect(
            coordinator.normalize(event: .standalonePressed, mode: .hold, state: .idle),
            [.pressed],
            "hold mode starts on standalone press"
        )
        try expect(
            coordinator.normalize(event: .standaloneReleased, mode: .hold, state: .recording),
            [.released],
            "hold mode stops on standalone release"
        )
    }
}
