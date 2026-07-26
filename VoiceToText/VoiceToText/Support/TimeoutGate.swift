import Foundation

/// One-shot resolve gate for racing a real result against a timeout: whichever
/// side calls `resolve()` first wins and is the only one allowed to resume the
/// continuation. Shared by `ModelRegistry`'s preparation stall watchdog and
/// `AudioRecorder`'s engine-start timeout.
nonisolated final class TimeoutGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false

    var isResolved: Bool {
        lock.lock(); defer { lock.unlock() }
        return resolved
    }

    func resolve() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if resolved { return false }
        resolved = true
        return true
    }
}
