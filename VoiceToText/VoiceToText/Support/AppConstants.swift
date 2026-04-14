import AVFoundation
import Foundation

enum WindowID {
    static let main = "main"
}

enum AudioConfig {
    static let targetSampleRate: Double = 16_000
    static let tapBufferSize: AVAudioFrameCount = 4_096
}

enum DictationConfig {
    static let liveTranscriptionInterval: Duration = .milliseconds(500)
    static let minLiveSamples = 8_000
    static let enableAudioPreprocessing: Bool = true

    // Chunked streaming
    static let firstChunkSamples = 16_000   // ~1 s — fast first feedback
    static let chunkSamples = 40_000        // ~2.5 s at 16 kHz — steady state
    static let overlapSamples = 8_000       // ~0.5 s overlap between chunks
    static let overlapWords = 10            // word-level dedup window

    // Energy VAD
    static let vadFrameMs = 30             // RMS frame length in ms
    static let vadThresholdDBFS: Float = -45.0
    static let vadVoicedRatio: Float = 0.30
}
