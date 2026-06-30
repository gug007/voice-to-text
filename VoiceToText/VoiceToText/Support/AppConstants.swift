import AVFoundation
import Foundation

enum WindowID {
    static let main = "main"
}

enum AppURLScheme {
    /// Custom URL scheme registered in Info.plist (CFBundleURLTypes). Lets other
    /// apps trigger dictation, e.g. `open voicetotext://toggle`. Commands are
    /// parsed by DictationController.ExternalCommand.
    static let scheme = "voicetotext"
}

enum AudioConfig {
    static let targetSampleRate: Double = 16_000
    // 1024 frames @ 16 kHz = 64 ms — small enough for responsive live updates
    // while still giving AVAudioEngine's input thread headroom.
    static let tapBufferSize: AVAudioFrameCount = 1_024
}

enum DictationConfig {
    static let enableAudioPreprocessing: Bool = true
    static let minTranscribeSamples = 8_000

    // VAD defaults (overridable via VadTuning / Settings UI)
    static let vadFrameMs = 30             // RMS frame length in ms
    static let vadThresholdDBFS: Float = -45.0
    static let vadVoicedRatio: Float = 0.30
    static let sileroVoicedRatio: Float = 0.25
}

extension TimeInterval {
    /// Clock-style duration for the UI: "1:02:33" past an hour, "12:05" under it.
    var formattedClock: String {
        let total = max(0, Int(rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
