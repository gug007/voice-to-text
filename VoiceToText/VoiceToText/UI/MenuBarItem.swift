import AppKit
import Observation
import Symbols

/// Status-bar item: opens the main window, starts/stops dictation, and doubles
/// as the recording indicator. Optional on its own; mandatory while the Dock
/// icon is hidden, since it's then the app's only visible affordance. Owned and
/// driven solely by `AppPresenceController`, which decides when it's visible.
///
/// The glyph is an *instrument*, not a logo: every dictation state gets its own
/// symbol, tint and animation, so preparing / recording / transcribing /
/// reviewing / error are all distinguishable from outside the app. It renders
/// into an `NSImageView` hosted in the status button rather than
/// `button.image`, because symbol effects (`.variableColor`, `.pulse`,
/// `.bounce`) and the `.replace.downUp` content transition exist on
/// `NSImageView` only — `NSButton` has no such API in the macOS 26 SDK.
///
/// The elapsed clock lives in the **menu**, never in the status-item title. An
/// item whose title changes width every second forces AppKit to relayout the
/// status bar on every tick, which visibly reflows every extra to its left.
@MainActor
final class MenuBarItem: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    /// The 16pt symbol, centred in the square status item. Owned here so symbol
    /// effects can be added and removed as the state changes.
    private var glyphView: NSImageView?
    /// What the glyph currently draws, so a redundant refresh doesn't restart a
    /// running animation (which reads as a stutter every time the HUD updates).
    private var renderedGlyph: Glyph?
    /// Whether an observation chain for the dictation state is live. The chain
    /// re-arms itself after every change, so it must only be started once.
    private var isTrackingDictationState = false

    /// The disabled "Recording · 1:23" row, retained while the menu is open so
    /// the clock can tick in place.
    private var elapsedItem: NSMenuItem?
    /// The Start/Stop Dictation row, retained for the same reason: dictation can
    /// start while the menu is up (the standalone-modifier hotkey is a
    /// CGEventTap, which — unlike a Carbon hotkey — still fires during menu
    /// tracking), and the row has to follow the state instead of freezing.
    private var dictationMenuItem: NSMenuItem?
    /// Whether the menu is currently tracking. `menuNeedsUpdate` and
    /// `menuWillOpen` have both already run by then and will not run again
    /// until the next open, so a state change arriving mid-tracking is the only
    /// thing that can keep the open menu honest.
    private var isMenuOpen = false
    /// Drives that tick. A `Timer` on `.common` run-loop modes, because menu
    /// tracking runs the main loop in `NSEventTrackingRunLoopMode` and a plain
    /// default-mode timer would simply stop for as long as the menu is open.
    private var elapsedTimer: Timer?

    /// The glyph's point size. 16pt is the menu-bar norm; the item itself is
    /// square (`squareLength` == the status bar's own thickness), so the glyph
    /// is optically centred in the working height rather than hand-positioned.
    private static let glyphPointSize: CGFloat = 16
    /// Menu rows carry 16pt symbols — macOS 26 renders `NSMenuItem.image` for
    /// the first time, and 27 condenses the bar, so the icon is what survives.
    private static let menuIconPointSize: CGFloat = 16

    func setVisible(_ visible: Bool) {
        if visible { install() } else { remove() }
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "VoiceToText"
        installGlyphView(in: item.button)

        let menu = NSMenu()
        menu.delegate = self
        // Items are enabled/disabled from the live dictation state below;
        // automatic enabling would override that.
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        refreshGlyph(animated: false)
        startTrackingDictationState()
    }

    private func remove() {
        stopElapsedTicker()
        isMenuOpen = false
        glyphView?.removeFromSuperview()
        glyphView = nil
        renderedGlyph = nil
        elapsedItem = nil
        dictationMenuItem = nil
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    // MARK: - Glyph

    /// One row per dictation state. Symbol, tint and animation are derived
    /// together so a state can never end up looking like a different one.
    private enum Glyph: Equatable {
        case idle
        case preparing
        case recording
        case transcribing
        case reviewing
        case error

        var symbol: String {
            switch self {
            case .idle, .recording: return "waveform"
            case .preparing: return "arrow.down.circle"
            case .transcribing: return "waveform.badge.magnifyingglass"
            case .reviewing: return "text.cursor"
            case .error: return "exclamationmark.triangle.fill"
            }
        }

        /// nil = the system label colour, i.e. whatever the menu bar wants.
        /// Only the two states that need to be readable across the room are
        /// tinted; `reviewing` deliberately is not — the review HUD already
        /// carries that state and the menu bar must not compete with it.
        var tint: NSColor? {
            switch self {
            case .recording: return Palette.signalLiveNS
            case .error: return Palette.signalWarnNS
            case .idle, .preparing, .transcribing, .reviewing: return nil
            }
        }

        var animation: Animation {
            switch self {
            case .preparing: return .variableColorCumulative
            case .recording: return .variableColorIterative
            case .transcribing: return .pulse
            case .error: return .bounce
            case .idle, .reviewing: return .none
            }
        }

        /// Spoken by VoiceOver and shown as the item's tooltip.
        var label: String {
            switch self {
            case .idle: return "VoiceToText"
            case .preparing: return "VoiceToText — loading model"
            case .recording: return "VoiceToText — recording"
            case .transcribing: return "VoiceToText — transcribing"
            case .reviewing: return "VoiceToText — reviewing transcript"
            case .error: return "VoiceToText — needs attention"
            }
        }

        /// `.bounce` fires once on entry; the rest run until the state changes.
        enum Animation {
            case none
            case variableColorCumulative
            case variableColorIterative
            case pulse
            case bounce
        }

        init(_ state: DictationController.State) {
            switch state {
            case .idle: self = .idle
            case .preparing: self = .preparing
            case .recording: self = .recording
            case .transcribing: self = .transcribing
            case .reviewing: self = .reviewing
            case .error: self = .error
            }
        }
    }

    /// Hosts the symbol in the status button. The button keeps drawing its own
    /// highlight behind this view when the menu opens.
    private func installGlyphView(in button: NSStatusBarButton?) {
        guard let button else { return }
        let view = GlyphView()
        view.imageScaling = .scaleProportionallyDown
        view.imageAlignment = .alignCenter
        view.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            view.widthAnchor.constraint(lessThanOrEqualTo: button.widthAnchor),
            view.heightAnchor.constraint(lessThanOrEqualTo: button.heightAnchor)
        ])
        glyphView = view
    }

    /// Swaps the glyph, tint and animation to match the live dictation state.
    /// A no-op when nothing changed, so a repeated refresh can't restart a
    /// running `.variableColor` cycle mid-stroke.
    private func refreshGlyph(animated: Bool) {
        guard let button = statusItem?.button, let view = glyphView else { return }
        let glyph = Glyph(DictationController.shared.state)
        guard glyph != renderedGlyph else { return }
        let isFirstDraw = renderedGlyph == nil
        renderedGlyph = glyph

        let image = NSImage(systemSymbolName: glyph.symbol, accessibilityDescription: glyph.label)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: Self.glyphPointSize, weight: .regular)
            )
        // Template so the menu bar tints it — light bar, dark bar, Reduce
        // Transparency's flat grey and the notched 43pt bar all come free, and
        // an explicit `contentTintColor` still wins where a state needs one.
        image?.isTemplate = true

        view.removeAllSymbolEffects()
        if let image {
            if animated && !isFirstDraw && !Self.reduceMotion {
                view.setSymbolImage(image, contentTransition: .replace.downUp)
            } else {
                view.image = image
            }
        }
        view.contentTintColor = glyph.tint
        applyAnimation(glyph.animation, to: view)

        button.toolTip = glyph.label
        button.setAccessibilityLabel(glyph.label)
    }

    private func applyAnimation(_ animation: Glyph.Animation, to view: NSImageView) {
        // Every effect used here is macOS 14+, so the 15.0 floor needs no gate.
        // Reduce Motion drops the loops; the glyph and tint still tell the
        // states apart, which is the part that carries meaning.
        guard !Self.reduceMotion else { return }
        switch animation {
        case .none:
            break
        case .variableColorCumulative:
            view.addSymbolEffect(.variableColor.cumulative, options: .repeating)
        case .variableColorIterative:
            view.addSymbolEffect(.variableColor.iterative, options: .repeating)
        case .pulse:
            view.addSymbolEffect(.pulse, options: .repeating)
        case .bounce:
            view.addSymbolEffect(.bounce, options: .nonRepeating)
        }
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
            // `guard let` first: an inner Task capturing the weak `self` *var*
            // is a concurrent capture of a mutable binding, which Swift 6 makes
            // an error. Binding it here hands the Task an immutable reference —
            // and the reference is safe to send because the class is
            // MainActor-isolated, hence implicitly Sendable.
            guard let self else { return }
            // onChange fires *before* the value is written, so read it back on
            // the next main-actor turn — and re-arm, since tracking is one-shot.
            Task { @MainActor in
                self.handleDictationStateChange()
            }
        }
    }

    private func handleDictationStateChange() {
        guard statusItem != nil else {
            isTrackingDictationState = false
            return
        }
        refreshGlyph(animated: true)
        // The menu can be open across a state change (Stop Dictation is one
        // click away from `.transcribing`, and the standalone-modifier hotkey
        // fires straight through menu tracking); keep its rows honest.
        refreshElapsedItem()
        if isMenuOpen {
            refreshDictationItem()
            // `menuWillOpen` already ran and won't run again, so a recording
            // that begins while the menu is up has to start its own ticker —
            // and one that ends has to stop it. `startElapsedTicker` does both:
            // it invalidates first and bails out when nothing is recording.
            startElapsedTicker()
        }
        trackNextDictationStateChange()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        elapsedItem = nil
        dictationMenuItem = nil

        menu.addItem(item(
            title: "Open VoiceToText",
            symbol: "macwindow",
            action: #selector(openMainWindow)
        ))
        menu.addItem(.separator())

        // Elapsed time lives here, not in the status-item title.
        let elapsed = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        elapsed.image = Self.menuIcon("record.circle")
        elapsed.isEnabled = false
        menu.addItem(elapsed)
        elapsedItem = elapsed
        refreshElapsedItem()

        let dictation = item(
            title: dictationItem.title,
            symbol: dictationItem.symbol,
            action: #selector(toggleDictation)
        )
        dictation.isEnabled = dictationItem.isEnabled
        dictation.toolTip = "Or press \(HotkeyStore.shared.binding.displayKeys.joined()) from any app."
        menu.addItem(dictation)
        dictationMenuItem = dictation

        menu.addItem(.separator())
        let quit = item(title: "Quit VoiceToText", symbol: "power", action: #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        startElapsedTicker()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        // The ticker only ever exists while the menu is tracking: nothing else
        // starts it, and this is the one path out of tracking.
        stopElapsedTicker()
    }

    private func item(title: String, symbol: String, action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.image = Self.menuIcon(symbol)
        return menuItem
    }

    /// A 16pt template symbol for a menu row. The AppKit spelling of
    /// `.labelStyle(.titleAndIcon)`: `NSMenu` has no label style, the icon is
    /// simply the item's image.
    private static func menuIcon(_ symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: menuIconPointSize, weight: .regular)
            )
        image?.isTemplate = true
        return image
    }

    /// Label and enablement for the dictation row, derived together with its
    /// symbol so the three can't drift apart.
    private var dictationItem: (title: String, symbol: String, isEnabled: Bool) {
        switch DictationController.shared.state {
        case .idle, .error: return ("Start Dictation", "mic.circle.fill", true)
        case .preparing: return ("Loading Model…", "arrow.down.circle", false)
        case .recording: return ("Stop Dictation", "stop.circle.fill", true)
        case .transcribing: return ("Transcribing…", "waveform.badge.magnifyingglass", false)
        case .reviewing: return ("Reviewing Transcript…", "text.cursor", false)
        }
    }

    /// Rewrites the dictation row in place from the live state, for when it
    /// changes while the menu is already on screen. Same tuple that built the
    /// row, so title, icon and enablement still can't drift apart.
    private func refreshDictationItem() {
        guard let dictationMenuItem else { return }
        let spec = dictationItem
        dictationMenuItem.title = spec.title
        dictationMenuItem.image = Self.menuIcon(spec.symbol)
        dictationMenuItem.isEnabled = spec.isEnabled
    }

    // MARK: - Elapsed clock

    /// Rewrites the clock row in place. Hidden outside `.recording`, so the menu
    /// never carries a stale time.
    private func refreshElapsedItem() {
        guard let elapsedItem else { return }
        guard let elapsed = DictationController.shared.recordingElapsedSeconds else {
            elapsedItem.isHidden = true
            return
        }
        elapsedItem.isHidden = false
        // An attributed title: a disabled row's plain title is drawn dimmed,
        // and the recording clock is the one thing in this menu that has to
        // stay readable. SF Mono with monospaced digits so it doesn't jitter.
        let title = NSMutableAttributedString(
            string: "Recording · \(elapsed.formattedClock)",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: Palette.signalLiveNS
            ]
        )
        elapsedItem.attributedTitle = title
    }

    private func startElapsedTicker() {
        stopElapsedTicker()
        guard DictationController.shared.recordingElapsedSeconds != nil else { return }
        // Target/action rather than the block form: the block is `@Sendable`,
        // and capturing this MainActor-isolated object in one is a Swift 6
        // concurrency error.
        let timer = Timer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(tickElapsed),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    private func stopElapsedTicker() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    @objc private func tickElapsed() {
        refreshElapsedItem()
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

/// The status item's symbol layer. `NSImageView` is an `NSControl`, so an
/// untouched instance sitting on top of `NSStatusBarButton` would swallow the
/// click that opens the menu — this one is transparent to hit-testing, leaving
/// the button the only thing the pointer can reach.
private final class GlyphView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
