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
    static let liveTranscriptionInterval: Duration = .milliseconds(800)
    static let minLiveSamples = 8_000
}
