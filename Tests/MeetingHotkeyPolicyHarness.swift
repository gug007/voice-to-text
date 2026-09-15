import Foundation

struct MeetingPolicyHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(
    _ actual: MeetingHotkeyAction,
    _ expected: MeetingHotkeyAction,
    _ message: String
) throws {
    if actual != expected {
        throw MeetingPolicyHarnessFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

@main
struct MeetingHotkeyPolicyHarness {
    static func main() throws {
        try expect(
            MeetingHotkeyPolicy.action(state: .idle),
            .start,
            "press starts a conversation from idle"
        )
        try expect(
            MeetingHotkeyPolicy.action(state: .recording),
            .stopAndTranscribe,
            "press stops and transcribes while recording"
        )
        try expect(
            MeetingHotkeyPolicy.action(state: .busy),
            .none,
            "press is swallowed while transcribing, importing or mid-transition"
        )
        print("Meeting hotkey policy harness passed")
    }
}
