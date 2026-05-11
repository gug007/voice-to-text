import Foundation

struct HarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(
    _ actual: DictationHotkeyAction,
    _ expected: DictationHotkeyAction,
    _ message: String
) throws {
    if actual != expected {
        throw HarnessFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

@main
struct HotkeyBehaviorHarness {
    static func main() throws {
        try expect(
            DictationHotkeyPolicy.action(mode: .hold, state: .idle, event: .pressed),
            .startRecording,
            "hold press starts from idle"
        )
        try expect(
            DictationHotkeyPolicy.action(mode: .hold, state: .recording, event: .released),
            .stopAndTranscribe,
            "hold release stops while recording"
        )
        try expect(
            DictationHotkeyPolicy.action(mode: .hold, state: .preparing, event: .released),
            .cancelPendingRecording,
            "hold release cancels while preparing"
        )
        try expect(
            DictationHotkeyPolicy.action(mode: .hold, state: .recording, event: .pressed),
            .none,
            "hold duplicate press does not restart"
        )
        try expect(
            DictationHotkeyPolicy.action(mode: .toggle, state: .recording, event: .released),
            .none,
            "toggle release is ignored"
        )
        try expect(
            DictationHotkeyPolicy.action(mode: .toggle, state: .reviewing, event: .pressed),
            .confirmPaste,
            "toggle press confirms review"
        )
        try expect(
            DictationHotkeyPolicy.action(mode: .hold, state: .reviewing, event: .pressed),
            .confirmPaste,
            "hold press confirms review"
        )

        print("Hotkey behavior harness passed")
    }
}
