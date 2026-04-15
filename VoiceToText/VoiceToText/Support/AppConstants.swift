import AVFoundation
import Foundation

enum WindowID {
    static let main = "main"
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
