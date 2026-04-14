import Foundation
import OSLog

enum AppLog {
    private static let subsystem = "voice-to-text-ai.VoiceToText"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let dictation = Logger(subsystem: subsystem, category: "Dictation")
    static let engine = Logger(subsystem: subsystem, category: "Engine")
    static let hud = Logger(subsystem: subsystem, category: "HUD")
    static let audio = Logger(subsystem: subsystem, category: "Audio")
}
