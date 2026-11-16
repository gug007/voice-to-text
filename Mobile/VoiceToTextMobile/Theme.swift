import SwiftUI

enum Palette {
    static let ink = Color.primary
    static let accent = Color.accentColor
    static let live = Color(red: 0xD2 / 255, green: 0x2C / 255, blue: 0x33 / 255)
    static let ready = Color(red: 0x00 / 255, green: 0x7A / 255, blue: 0x76 / 255)
}

enum DurationFormat {
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
