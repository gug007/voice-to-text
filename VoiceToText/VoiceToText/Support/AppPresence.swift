import AppKit
import Observation

/// Where VoiceToText shows up on the system: the Dock icon and the menu bar
/// item. Turning the Dock icon off switches the process to `.accessory`, which
/// also drops the app's menu bar — so the status item is forced on for as long
/// as the Dock icon stays hidden, otherwise there'd be no way back to the
/// window.
@MainActor
@Observable
final class AppPresenceController {
    static let shared = AppPresenceController()

    private enum Key {
        static let showsDockIcon = "presence.showsDockIcon"
        static let wantsMenuBarIcon = "presence.wantsMenuBarIcon"
    }

    /// Dock icon and app-switcher entry. Off ⇒ the app runs as an accessory,
    /// living in the menu bar only.
    var showsDockIcon: Bool {
        didSet {
            guard showsDockIcon != oldValue else { return }
            defaults.set(showsDockIcon, forKey: Key.showsDockIcon)
            applyDockPolicy()
            syncMenuBarItem()
        }
    }

    /// The user's own menu bar choice — on by default. Kept separate from
    /// `showsMenuBarIcon` so a spell with the Dock icon hidden doesn't quietly
    /// rewrite it: turn the Dock icon back on and the item returns to whatever
    /// they actually picked.
    var wantsMenuBarIcon: Bool {
        didSet {
            guard wantsMenuBarIcon != oldValue else { return }
            defaults.set(wantsMenuBarIcon, forKey: Key.wantsMenuBarIcon)
            syncMenuBarItem()
        }
    }

    /// Whether the status item is actually installed.
    var showsMenuBarIcon: Bool { wantsMenuBarIcon || isMenuBarIconLocked }

    /// Whether the menu bar item can't be switched off right now. The UI reads
    /// this instead of restating the rule behind it.
    var isMenuBarIconLocked: Bool { !showsDockIcon }

    /// What the menu bar switch binds to: it shows the effective state (the
    /// item is forced on while the Dock icon is hidden) but writes through to
    /// the user's own preference, so the UI carries none of that rule.
    var menuBarIconSetting: Bool {
        get { showsMenuBarIcon }
        set { wantsMenuBarIcon = newValue }
    }

    private let defaults = UserDefaults.standard
    private let menuBarItem = MenuBarItem()

    private init() {
        defaults.register(defaults: [Key.showsDockIcon: true, Key.wantsMenuBarIcon: true])
        showsDockIcon = defaults.bool(forKey: Key.showsDockIcon)
        wantsMenuBarIcon = defaults.bool(forKey: Key.wantsMenuBarIcon)
    }

    /// Puts the process in the right activation policy. Called at launch from
    /// `applicationWillFinishLaunching` — before the first window is placed, so
    /// a Dock-hidden launch never flashes an icon into the Dock. NSApp is nil
    /// any earlier than that, hence the optional chain.
    func applyDockPolicy() {
        NSApp?.setActivationPolicy(showsDockIcon ? .regular : .accessory)
    }

    /// Installs or removes the status item to match `showsMenuBarIcon`. Called
    /// at launch from `applicationDidFinishLaunching` — the status bar isn't up
    /// any earlier.
    func syncMenuBarItem() {
        menuBarItem.setVisible(showsMenuBarIcon)
    }
}
