import AppKit
import Carbon.HIToolbox
import Foundation

struct RecordingEscapePolicyHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw RecordingEscapePolicyHarnessFailure(description: message)
    }
}

@main
struct RecordingEscapePolicyHarness {
    static func main() throws {
        try expect(
            RecordingEscapePolicy.shouldCancel(keyCode: UInt16(kVK_Escape), modifierFlags: []),
            "bare Escape cancels recording"
        )
        try expect(
            !RecordingEscapePolicy.shouldCancel(keyCode: UInt16(kVK_Escape), modifierFlags: .option),
            "modified Escape is left available for configured shortcuts"
        )
        try expect(
            !RecordingEscapePolicy.shouldCancel(keyCode: UInt16(kVK_ANSI_M), modifierFlags: []),
            "non-Escape keys do not cancel recording"
        )

        print("Recording escape policy harness passed")
    }
}
