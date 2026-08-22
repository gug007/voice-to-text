import AppKit
import Observation

/// Which appearance VoiceToText paints in. `system` is the default and the only
/// value that lets macOS drive — including its automatic light/dark schedule.
nonisolated enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The AppKit appearance to pin the process to, or `nil` for "follow macOS".
    ///
    /// Increase Contrast has to be carried across by hand: plain `.aqua` /
    /// `.darkAqua` drop the high-contrast variant, and with it the
    /// `\.colorSchemeContrast` that `Tokens.swift` reads for every hairline and
    /// `inkFaint`. Pinning light or dark must not quietly cost the user that.
    func nsAppearance(increaseContrast: Bool) -> NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: increaseContrast ? .accessibilityHighContrastAqua : .aqua)
        case .dark:
            return NSAppearance(named: increaseContrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
        }
    }
}

/// The app-wide light/dark choice. It sets `NSApp.appearance`, so one value
/// covers every window in the process — settings, permission gate, popovers and
/// the dictation HUD — and no view has to branch on `\.colorScheme`: the
/// `Palette` tokens re-resolve themselves against whatever this pins.
@MainActor
@Observable
final class AppearanceController {
    static let shared = AppearanceController()

    private enum Key {
        static let mode = "appearance.mode"
    }

    var mode: AppAppearance {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Key.mode)
            apply()
        }
    }

    private let defaults = UserDefaults.standard
    private var contrastObserver: (any NSObjectProtocol)?

    private init() {
        defaults.register(defaults: [Key.mode: AppAppearance.system.rawValue])
        mode = AppAppearance(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .system
    }

    /// Pins (or unpins) the process appearance. Called at launch from
    /// `applicationWillFinishLaunching` — before the first window is placed, so a
    /// dark-pinned launch never flashes a light window. NSApp is nil any earlier
    /// than that, hence the optional chain.
    func apply() {
        NSApp?.appearance = mode.nsAppearance(increaseContrast: Self.increaseContrast)
    }

    /// Keeps a pinned appearance in step with the Increase Contrast switch.
    /// While we're on `system` macOS swaps the variant for us; the moment we pin
    /// one, that stops, and this is what puts it back. Idempotent, so the
    /// notification firing for Reduce Motion / Transparency too costs nothing.
    func startObservingContrastChanges() {
        guard contrastObserver == nil else { return }
        contrastObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in AppearanceController.shared.apply() }
        }
    }

    private static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
}
