import AppKit
import Observation

/// Status-bar item: opens the main window, starts/stops dictation, and doubles
/// as the recording indicator. Optional on its own; mandatory while the Dock
/// icon is hidden, since it's then the app's only visible affordance. Owned and
/// driven solely by `AppPresenceController`, which decides when it's visible.
@MainActor
final class MenuBarItem: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    /// Whether an observation chain for the dictation state is live. The chain
    /// re-arms itself after every change, so it must only be started once.
    private var isTrackingDictationState = false

    func setVisible(_ visible: Bool) {
        if visible { install() } else { remove() }
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoiceToText")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "VoiceToText"
        let menu = NSMenu()
        menu.delegate = self
        // Items are enabled/disabled from the live dictation state below;
        // automatic enabling would override that.
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        refreshIcon()
        startTrackingDictationState()
    }

    private func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    // MARK: - Icon

    /// Tints the icon red while recording so the item reads as a recording
    /// indicator at a glance, without having to look at the HUD.
    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let isRecording = DictationController.shared.state == .recording
        button.image?.accessibilityDescription = isRecording ? "VoiceToText — recording" : "VoiceToText"
        button.contentTintColor = isRecording ? .systemRed : nil
    }

    private func startTrackingDictationState() {
        guard !isTrackingDictationState else { return }
        isTrackingDictationState = true
        trackNextDictationStateChange()
    }

    private func trackNextDictationStateChange() {
        withObservationTracking {
            _ = DictationController.shared.state
        } onChange: { [weak self] in
            // onChange fires *before* the value is written, so read it back on
            // the next main-actor turn — and re-arm, since tracking is one-shot.
            Task { @MainActor in
                self?.handleDictationStateChange()
            }
        }
    }

    private func handleDictationStateChange() {
        guard statusItem != nil else {
            isTrackingDictationState = false
            return
        }
        refreshIcon()
        trackNextDictationStateChange()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item(title: "Open VoiceToText", action: #selector(openMainWindow)))
        menu.addItem(.separator())

        let dictation = item(title: dictationItem.title, action: #selector(toggleDictation))
        dictation.isEnabled = dictationItem.isEnabled
        dictation.toolTip = "Or press \(HotkeyStore.shared.binding.displayKeys.joined()) from any app."
        menu.addItem(dictation)

        menu.addItem(.separator())
        let quit = item(title: "Quit VoiceToText", action: #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(title: String, action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    /// Label and enablement for the dictation row, derived together so the two
    /// can't drift apart.
    private var dictationItem: (title: String, isEnabled: Bool) {
        switch DictationController.shared.state {
        case .idle, .error: return ("Start Dictation", true)
        case .preparing: return ("Loading Model…", false)
        case .recording: return ("Stop Dictation", true)
        case .transcribing: return ("Transcribing…", false)
        case .reviewing: return ("Reviewing Transcript…", false)
        }
    }

    // MARK: - Actions

    @objc private func openMainWindow() {
        WindowOpener.shared.showMain()
    }

    @objc private func toggleDictation() {
        DictationController.shared.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
