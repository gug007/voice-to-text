#if arch(x86_64)
import Foundation
import OSLog

/// Whether the transcribe.cpp worker may use the Mac's GPU: the user's
/// "Use graphics card" switch in the Models pane, and whether the GPU has
/// already failed on this Mac.
///
/// A GPU failure is remembered across launches. An Intel Mac's GPU driver that
/// crashes or hangs under Metal does so every time, so without the flag each
/// launch would cost the user one crashed or timed-out transcription before
/// the CPU took over. Turning the switch either way clears it, which is how
/// the user asks for the GPU to be tried again.
nonisolated enum TranscribeGPUPreference {
    enum Keys {
        static let useGPU = "transcribeCpp.useGPU"
        /// What failed, in a sentence for the log. Present means failed.
        static let gpuFailure = "transcribeCpp.gpuFailure"
    }

    /// The switch, on unless the user turned it off.
    static var useGPU: Bool {
        UserDefaults.standard.object(forKey: Keys.useGPU) as? Bool ?? true
    }

    static var gpuFailed: Bool {
        UserDefaults.standard.string(forKey: Keys.gpuFailure) != nil
    }

    /// Whether a new worker may register the GPU backends.
    static var allowsGPU: Bool { useGPU && !gpuFailed }

    static func markGPUFailed(_ reason: String) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Keys.gpuFailure) == nil else { return }
        defaults.set(reason, forKey: Keys.gpuFailure)
        AppLog.engine.error("Transcription GPU marked as failed on this Mac; using the CPU from now on: \(reason, privacy: .public)")
    }

    /// The user turned the switch: honour it, and try the GPU again.
    static func setUseGPU(_ isOn: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(isOn, forKey: Keys.useGPU)
        if defaults.string(forKey: Keys.gpuFailure) != nil {
            defaults.removeObject(forKey: Keys.gpuFailure)
            AppLog.engine.info("Transcription GPU failure cleared by the user")
        }
    }
}
#endif
