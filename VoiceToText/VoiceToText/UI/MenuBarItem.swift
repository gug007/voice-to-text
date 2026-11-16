import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI
import Symbols

/// Status-bar item: opens the main window, starts/stops dictation and
/// conversation recording, and doubles as the recording indicator. Optional on
/// its own; mandatory while the Dock icon is hidden, since it's then the app's
/// only visible affordance. Owned and driven solely by `AppPresenceController`,
/// which decides when it's visible.
///
/// The glyph is an *instrument*, not a logo: every state gets its own symbol,
/// tint and animation, so preparing / recording / transcribing / reviewing /
/// error — dictation's and a conversation's alike — are all distinguishable
/// from outside the app. That matters most for a conversation, which is
/// normally started by shortcut from another app and has no other visible
/// confirmation. It renders into an `NSImageView` hosted in the status button
/// rather than `button.image`, because symbol effects (`.variableColor`,
/// `.pulse`, `.bounce`) and the `.replace.downUp` content transition exist on
/// `NSImageView` only — `NSButton` has no such API in the macOS 26 SDK.
///
/// The elapsed clocks live in the **menu**, never in the status-item title. An
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
    /// Whether an observation chain for the two controllers' states is live. The
    /// chain re-arms itself after every change, so it must only be started once.
    private var isTrackingState = false

    /// The disabled status row at the top ("Ready · GPT Transcribe", or
    /// "Recording · 1:23"), retained while the menu is open so the clock can
    /// tick in place.
    private var statusMenuItem: NSMenuItem?
    private var statusView: MenuStatusView?
    /// The fix under the status row ("Open Cloud…"), shown only while
    /// dictation can't run.
    private var statusFixMenuItem: NSMenuItem?
    /// The Start/Stop Dictation row, retained for the same reason: dictation can
    /// start while the menu is up (the standalone-modifier hotkey is a
    /// CGEventTap, which — unlike a Carbon hotkey — still fires during menu
    /// tracking), and the row has to follow the state instead of freezing.
    private var dictationMenuItem: NSMenuItem?
    /// The conversation action row. Its shortcut is a Carbon hotkey, so it can't
    /// fire during menu tracking — but a recording started earlier keeps
    /// running, and its transcription can finish, while the menu is up.
    private var conversationMenuItem: NSMenuItem?
    /// Transcribe File…, enabled only while Upload File… would be: the import
    /// shares the conversation recorder, which can start or finish underneath.
    private var transcribeFileMenuItem: NSMenuItem?
    /// The Model row, retained so a dictation starting while the menu is up
    /// disables it.
    private var modelMenuRow: NSMenuItem?
    /// Copy Last Transcript, retained so a take that lands in History while
    /// the menu is up enables it.
    private var copyLastMenuItem: NSMenuItem?
    /// Whether the menu is currently tracking. `menuNeedsUpdate` and
    /// `menuWillOpen` have both already run by then and will not run again
    /// until the next open, so a state change arriving mid-tracking is the only
    /// thing that can keep the open menu honest.
    private var isMenuOpen = false
    /// Drives those ticks. A `Timer` on `.common` run-loop modes, because menu
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
        // Items are enabled/disabled from the live controller states below;
        // automatic enabling would override that.
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        refreshGlyph(animated: false)
        startTrackingState()
    }

    private func remove() {
        stopElapsedTicker()
        isMenuOpen = false
        glyphView?.removeFromSuperview()
        glyphView = nil
        renderedGlyph = nil
        statusMenuItem = nil
        statusView = nil
        statusFixMenuItem = nil
        dictationMenuItem = nil
        conversationMenuItem = nil
        transcribeFileMenuItem = nil
        copyLastMenuItem = nil
        modelMenuRow = nil
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    // MARK: - Glyph

    /// One row per state the status item can show. Symbol, tint and animation
    /// are derived together so a state can never end up looking like a
    /// different one.
    private enum Glyph: Equatable {
        case idle
        case preparing
        case recording
        case transcribing
        case reviewing
        case error
        case conversationRecording
        case conversationTranscribing

        var symbol: String {
            switch self {
            case .idle, .recording: return "waveform"
            case .preparing: return "arrow.down.circle"
            case .transcribing, .conversationTranscribing: return "waveform.badge.magnifyingglass"
            case .reviewing: return "text.cursor"
            case .error: return "exclamationmark.triangle.fill"
            case .conversationRecording: return "record.circle"
            }
        }

        /// nil = the system label colour, i.e. whatever the menu bar wants.
        /// Only the states that need to be readable across the room are tinted;
        /// `reviewing` deliberately is not — the review HUD already carries that
        /// state and the menu bar must not compete with it.
        var tint: NSColor? {
            switch self {
            case .recording, .conversationRecording: return Palette.signalLiveNS
            case .error: return Palette.signalWarnNS
            case .idle, .preparing, .transcribing, .reviewing, .conversationTranscribing: return nil
            }
        }

        var animation: Animation {
            switch self {
            case .preparing: return .variableColorCumulative
            case .recording: return .variableColorIterative
            case .transcribing, .conversationRecording, .conversationTranscribing: return .pulse
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
            case .conversationRecording: return "VoiceToText — recording conversation"
            case .conversationTranscribing: return "VoiceToText — transcribing conversation"
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
            // Idle, not transcribing: the card is already gone and the paste
            // lands within a second, so a pulse here would only flash between
            // the review glyph and the resting one.
            case .delivering: self = .idle
            case .error: self = .error
            }
        }

        /// Dictation wins whenever it is doing anything: it's the foreground
        /// interaction the user is standing there waiting on, while a
        /// conversation runs in the background for an hour at a time.
        /// A paste in flight counts as done here: it reads as idle anyway, and
        /// letting it win would blink a running conversation's glyph away for
        /// the second it takes.
        init(dictation: DictationController.State, meeting: MeetingController.State) {
            switch dictation {
            case .idle, .delivering:
                break
            case .preparing, .recording, .transcribing, .reviewing, .error:
                self.init(dictation)
                return
            }
            switch meeting {
            case .recording: self = .conversationRecording
            case .transcribing, .importing: self = .conversationTranscribing
            case .error: self = .error
            case .idle: self = .idle
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

    /// Swaps the glyph, tint and animation to match the live state. A no-op when
    /// nothing changed, so a repeated refresh can't restart a running
    /// `.variableColor` cycle mid-stroke.
    private func refreshGlyph(animated: Bool) {
        guard let button = statusItem?.button, let view = glyphView else { return }
        let glyph = Glyph(
            dictation: DictationController.shared.state,
            meeting: MeetingController.shared.state
        )
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

    private func startTrackingState() {
        guard !isTrackingState else { return }
        isTrackingState = true
        trackNextStateChange()
    }

    private func trackNextStateChange() {
        withObservationTracking {
            _ = DictationController.shared.state
            _ = MeetingController.shared.state
            // A take lands in History after the state goes idle; Copy Last
            // Transcript follows it.
            _ = RecordingHistoryStore.shared.entries
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
                self.handleStateChange()
            }
        }
    }

    private func handleStateChange() {
        guard statusItem != nil else {
            isTrackingState = false
            return
        }
        refreshGlyph(animated: true)
        // The menu can be open across a state change (Stop Dictation is one
        // click away from `.transcribing`, the standalone-modifier hotkey fires
        // straight through menu tracking, and a conversation keeps recording or
        // transcribing underneath); keep its rows honest.
        refreshStatusItem()
        if isMenuOpen {
            refreshDictationItem()
            refreshModelItem()
            refreshConversationItem()
            refreshCopyLastItem()
            // `menuWillOpen` already ran and won't run again, so a recording
            // that begins while the menu is up has to start its own ticker —
            // and one that ends has to stop it. `startElapsedTicker` does both:
            // it invalidates first and bails out when nothing is recording.
            startElapsedTicker()
        }
        trackNextStateChange()
    }

    // MARK: - Menu

    /// Status first, then the commands (with the global shortcuts as key
    /// equivalents), the model, the windows, Quit.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        statusMenuItem = nil
        statusView = nil
        statusFixMenuItem = nil
        dictationMenuItem = nil
        conversationMenuItem = nil
        transcribeFileMenuItem = nil
        copyLastMenuItem = nil
        modelMenuRow = nil

        // The sidebar chip's line, or the running clocks. Elapsed time lives
        // here, not in the status-item title.
        // A view, not a disabled item or a section header: both are drawn
        // dimmed, and this line has to read at full contrast.
        let status = NSMenuItem()
        let view = MenuStatusView()
        status.view = view
        menu.addItem(status)
        statusMenuItem = status
        statusView = view
        let fix = NSMenuItem(title: "", action: #selector(openStatusFix), keyEquivalent: "")
        fix.target = self
        menu.addItem(fix)
        statusFixMenuItem = fix
        refreshStatusItem()
        menu.addItem(.separator())

        let dictation = item(
            title: dictationItem.title,
            symbol: dictationItem.symbol,
            action: #selector(toggleDictation)
        )
        dictation.isEnabled = dictationItem.isEnabled
        Self.showShortcut(Self.dictationShortcut, on: dictation)
        dictation.toolTip = Self.shortcutTip(HotkeyStore.shared.binding)
        menu.addItem(dictation)
        dictationMenuItem = dictation

        let conversation = item(
            title: conversationItem.title,
            symbol: conversationItem.symbol,
            action: #selector(toggleConversation)
        )
        conversation.isEnabled = conversationItem.isEnabled
        Self.showShortcut(Self.conversationShortcut, on: conversation)
        // Only when there is one — the conversation shortcut is opt-in.
        conversation.toolTip = HotkeyStore.shared.meetingBinding.map(Self.shortcutTip)
        menu.addItem(conversation)
        conversationMenuItem = conversation

        let transcribeFile = item(
            title: "Transcribe File…",
            symbol: "waveform.badge.plus",
            action: #selector(transcribeFile)
        )
        transcribeFile.isEnabled = MediaFileImport.isAvailable
        transcribeFile.toolTip = "Transcribe an audio or video file already on this Mac."
        menu.addItem(transcribeFile)
        transcribeFileMenuItem = transcribeFile

        let copyLast = item(
            title: "Copy Last Transcript",
            symbol: "doc.on.doc",
            action: #selector(copyLastTranscript)
        )
        Self.showShortcut(Self.copyLastShortcut, on: copyLast)
        menu.addItem(copyLast)
        copyLastMenuItem = copyLast
        refreshCopyLastItem()

        menu.addItem(.separator())
        let model = modelMenuItem()
        model.isEnabled = canChangeModel
        menu.addItem(model)
        modelMenuRow = model

        // In the sidebar's order, each with a key equivalent.
        menu.addItem(.separator())
        let conversations = item(
            title: "Open Conversations",
            symbol: SettingsView.Section.meetings.icon,
            action: #selector(openConversations)
        )
        Self.showShortcut(Self.menuOnlyShortcut(key: "y", modifiers: [.command, .shift]), on: conversations)
        menu.addItem(conversations)
        let history = item(
            title: "Open History",
            symbol: SettingsView.Section.history.icon,
            action: #selector(openHistory)
        )
        Self.showShortcut(Self.menuOnlyShortcut(key: "y", modifiers: [.command]), on: history)
        menu.addItem(history)
        let settings = item(title: "Settings…", symbol: "gearshape", action: #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)

        alignModelName(in: model, menu: menu)

        menu.addItem(.separator())
        // With the Dock icon hidden there is no app menu, so this is the
        // only way to the About panel.
        menu.addItem(item(title: "About VoiceToText", symbol: "info.circle", action: #selector(showAbout)))
        // The quiet half of the update offer: only the first check of a
        // session prompts, so an update found later waits here (and on the
        // sidebar's Updates row) for as long as the app runs.
        if let version = AppUpdater.shared.indicatedVersion {
            menu.addItem(item(
                title: "Update Available — \(version)…",
                symbol: "arrow.down.circle",
                action: #selector(openUpdates)
            ))
        } else {
            menu.addItem(item(
                title: "Check for Updates…",
                symbol: "arrow.down.circle",
                action: #selector(checkForUpdates)
            ))
        }

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

    // MARK: - Shortcuts

    /// The dictation shortcut as a key equivalent, only while its global
    /// hotkey is registered. Display-only in practice: a registered Carbon
    /// hotkey takes its keystroke before any menu sees it, so with the menu
    /// open the shortcut fires the hotkey once and never this item too.
    /// Right Control alone has no key-equivalent form, so it shows nothing.
    private static var dictationShortcut: MenuShortcut? {
        let binding = HotkeyStore.shared.binding
        guard HotkeyManager.shared.isRegistered, !binding.isStandaloneModifier else { return nil }
        return MenuShortcut(binding)
    }

    /// The conversation shortcut, on the same terms.
    private static var conversationShortcut: MenuShortcut? {
        guard let binding = HotkeyStore.shared.meetingBinding,
              HotkeyManager.shared.isMeetingRegistered else { return nil }
        return MenuShortcut(binding)
    }

    /// ⇧⌘C, the review card's Copy chord, for Copy Last Transcript.
    private static var copyLastShortcut: MenuShortcut? {
        menuOnlyShortcut(key: "c", modifiers: [.command, .shift])
    }

    /// A key equivalent that only works while the menu is open — unless a
    /// global shortcut already owns the chord, in which case the hotkey would
    /// take the keystroke and the menu would show one chord on two rows.
    private static func menuOnlyShortcut(key: Character, modifiers: NSEvent.ModifierFlags) -> MenuShortcut? {
        guard let keyCode = menuOnlyKeyCodes[key] else { return nil }
        var carbon = 0
        if modifiers.contains(.command) { carbon |= cmdKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.control) { carbon |= controlKey }
        let chord = ShortcutKey(keyCode: UInt32(keyCode), modifiers: UInt32(carbon))
        let store = HotkeyStore.shared
        let taken = [store.binding, store.secondBinding, store.meetingBinding]
            .compactMap { $0?.shortcutKey }
            .contains(chord)
        return taken ? nil : MenuShortcut(key: String(key), modifiers: modifiers)
    }

    private static let menuOnlyKeyCodes: [Character: Int] = ["c": kVK_ANSI_C, "y": kVK_ANSI_Y]

    /// "Or press Control-Option-Shift-R from any app." — spelled out, and set
    /// whether or not the key equivalent shows (Right Control, a failed
    /// registration).
    private static func shortcutTip(_ binding: HotkeyBinding) -> String {
        "Or press \(Keycap.spokenName(for: binding.displayKeys)) from any app."
    }

    private static func showShortcut(_ shortcut: MenuShortcut?, on menuItem: NSMenuItem) {
        guard let shortcut else { return }
        menuItem.keyEquivalent = shortcut.key
        menuItem.keyEquivalentModifierMask = shortcut.modifiers
    }

    // MARK: - Status

    /// Rewrites the status row from the live state: the running clocks while
    /// anything records, otherwise `AppStatus` — the sidebar chip's words.
    /// The dot is a glyph in the title, not the item's image: the row reads
    /// the same whether or not the system draws menu icons.
    private func refreshStatusItem() {
        guard statusMenuItem != nil, let statusView else { return }
        let line = Self.statusLine
        // The state only; the Model row below names the model. Monospaced
        // digits so a running clock doesn't jitter.
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        let title = NSMutableAttributedString(
            string: "● ",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 2), .foregroundColor: line.tint, .baselineOffset: 1]
        )
        title.append(NSAttributedString(
            string: line.title,
            attributes: [
                .font: font,
                .foregroundColor: line.isLive ? Palette.signalLiveNS : NSColor.labelColor
            ]
        ))
        statusView.update(title, spoken: line.title)

        if let fixItem = statusFixMenuItem {
            fixItem.isHidden = line.fix == nil
            fixItem.title = line.fix?.label ?? ""
            fixItem.toolTip = line.fix?.tip
            fixItem.representedObject = line.fix?.section.rawValue
        }
    }

    private struct StatusLine {
        let title: String
        let tint: NSColor
        var isLive = false
        var fix: StatusFix?
    }

    /// Where the status row sends a click when dictation can't run.
    private struct StatusFix {
        let label: String
        let section: SettingsView.Section
        let tip: String
    }

    private static var statusLine: StatusLine {
        let dictationSeconds = DictationController.shared.recordingElapsedSeconds
        let conversationSeconds = conversationElapsedSeconds
        if let dictationSeconds {
            let conversation = conversationSeconds.map { " · conversation \($0.formattedClock)" } ?? ""
            return StatusLine(
                title: "Recording \(dictationSeconds.formattedClock)\(conversation)",
                tint: Palette.signalLiveNS,
                isLive: true
            )
        }
        if let conversationSeconds {
            return StatusLine(
                title: "Recording conversation \(conversationSeconds.formattedClock)",
                tint: Palette.signalLiveNS,
                isLive: true
            )
        }
        let status = AppStatus.current()
        return StatusLine(
            title: status.title,
            tint: tint(for: status.tone),
            fix: status.tone == .attention ? statusFix : nil
        )
    }

    /// A cloud model that can't run is fixed in Cloud (key, credit); anything
    /// else — no model, not downloaded, a failed download — in Models.
    private static var statusFix: StatusFix {
        if ModelRegistry.shared.activeModel?.isCloud == true {
            return StatusFix(label: "Open Cloud Settings…", section: .cloud, tip: "Add or check the API key in Cloud.")
        }
        return StatusFix(label: "Open Models…", section: .models, tip: "Download or choose a model in Models.")
    }

    private static func tint(for tone: AppStatus.Tone) -> NSColor {
        switch tone {
        case .ready: return NSColor(Palette.signalReady)
        case .busy: return .tertiaryLabelColor
        case .live: return Palette.signalLiveNS
        case .attention: return Palette.signalWarnNS
        }
    }

    // MARK: - Copy Last Transcript

    /// The newest History entry with a real transcript, of either kind.
    private static var lastTranscriptEntry: RecordingHistoryEntry? {
        RecordingHistoryStore.shared.entries
            .filter { !$0.transcriptIsPlaceholder && !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .max { $0.createdAt < $1.createdAt }
    }

    private func refreshCopyLastItem() {
        guard let copyLastMenuItem else { return }
        guard let entry = Self.lastTranscriptEntry else {
            copyLastMenuItem.isEnabled = false
            copyLastMenuItem.toolTip = RecordingHistoryStore.shared.isEnabled
                ? "Nothing in History yet."
                : "History is off, so there's no transcript to copy."
            return
        }
        copyLastMenuItem.isEnabled = true
        let when = Calendar.current.isDateInToday(entry.createdAt)
            ? entry.createdAt.formatted(date: .omitted, time: .shortened)
            : entry.createdAt.formatted(date: .abbreviated, time: .shortened)
        copyLastMenuItem.toolTip = "Copies the transcript from \(when)."
    }

    // MARK: - Model

    /// The Model row and its submenu of ready models. Disabled during a dictation
    /// (`canChangeModel`): the take reads the model when it stops, so a pick would land on it.
    private func modelMenuItem() -> NSMenuItem {
        let registry = ModelRegistry.shared
        // "Dictation Model": conversations can use another model.
        let menuItem = NSMenuItem(title: "Dictation Model", action: nil, keyEquivalent: "")
        menuItem.image = Self.menuIcon(SettingsView.Section.models.icon)

        let submenu = NSMenu(title: "Model")
        submenu.autoenablesItems = false
        // The same "can be chosen now" rule as the sidebar chip and Models.
        let ready = ModelCatalog.all.filter { ModelSwitchPolicy.isUsable($0, registry: registry) }
        for section in ModelGroup.sections(of: ready) {
            submenu.addItem(.sectionHeader(title: section.group.title))
            section.models.forEach { submenu.addItem(modelChoice($0, activeID: registry.activeModelId)) }
        }
        if ready.isEmpty {
            let none = NSMenuItem(title: "No models ready yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        }
        submenu.addItem(.separator())
        submenu.addItem(NSMenuItem(title: "All Models…", action: #selector(openModels), keyEquivalent: ""))
        submenu.items.last?.target = self
        menuItem.submenu = submenu
        return menuItem
    }

    private func modelChoice(_ model: ModelDescriptor, activeID: String) -> NSMenuItem {
        let choice = NSMenuItem(title: model.sectionedDisplayName, action: #selector(chooseModel(_:)), keyEquivalent: "")
        choice.target = self
        choice.representedObject = model.id
        choice.state = model.id == activeID ? .on : .off
        return choice
    }

    /// Sets the Model row's title to "Model" with the active model's name
    /// right-aligned in secondary ink, ending where the menu's widest title
    /// does so the row doesn't widen the menu. Run once the other rows exist.
    private func alignModelName(in menuItem: NSMenuItem, menu: NSMenu) {
        guard let model = ModelRegistry.shared.activeModel else { return }
        // The name only; the submenu's sections say where each model runs.
        let name = model.sectionedDisplayName
        let font = NSFont.menuFont(ofSize: 0)
        let width: (String) -> CGFloat = { ($0 as NSString).size(withAttributes: [.font: font]).width }
        let widestTitle = menu.items
            .filter { $0 !== menuItem && !$0.isSeparatorItem }
            .map { width($0.title) }
            .max() ?? 0
        let tabLocation = max(widestTitle, width(menuItem.title) + Space.s7 + width(name))
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: tabLocation)]
        // An attributed title keeps its own colours, so a disabled row is
        // dimmed here; a disabled row never highlights.
        var labelAttributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        if !menuItem.isEnabled { labelAttributes[.foregroundColor] = NSColor.disabledControlTextColor }
        let title = NSMutableAttributedString(string: menuItem.title, attributes: labelAttributes)
        title.append(NSAttributedString(
            string: "\t\(name)",
            attributes: [
                .font: font,
                .paragraphStyle: paragraph,
                .foregroundColor: menuItem.isEnabled ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
            ]
        ))
        menuItem.attributedTitle = title
        menuItem.toolTip = model.isCloud
            ? "Dictation uses \(model.sectionedDisplayName), which sends audio to the provider."
            : "Dictation uses \(model.sectionedDisplayName), on this Mac."
    }

    /// Whether the Model row may switch the dictation model — the shared rule
    /// (idle, or resting after an error), so the menu, the sidebar chip and
    /// Models agree.
    private var canChangeModel: Bool {
        ModelSwitchPolicy.canChangeDictationModel
    }

    private func refreshModelItem() {
        guard let modelMenuRow, let menu = modelMenuRow.menu,
              modelMenuRow.isEnabled != canChangeModel else { return }
        modelMenuRow.isEnabled = canChangeModel
        alignModelName(in: modelMenuRow, menu: menu)
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
        // Disabled like the other busy rows: the hotkey policy ignores a
        // toggle here, so an enabled row would be a button that does nothing.
        case .delivering: return ("Pasting…", "doc.on.clipboard", false)
        }
    }

    /// The same, for the conversation row. Mirrors `MeetingHotkeyPolicy`: the
    /// row is only enabled where a press would actually do something.
    private var conversationItem: (title: String, symbol: String, isEnabled: Bool) {
        switch MeetingController.shared.state {
        case .idle, .error: return ("Start Conversation", "record.circle", true)
        case .recording: return ("Stop & Transcribe Conversation", "stop.circle.fill", true)
        case .transcribing: return ("Transcribing Conversation…", "waveform.badge.magnifyingglass", false)
        case .importing: return ("Transcribing File…", "waveform.badge.magnifyingglass", false)
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

    private func refreshConversationItem() {
        guard let conversationMenuItem else { return }
        let spec = conversationItem
        conversationMenuItem.title = spec.title
        conversationMenuItem.image = Self.menuIcon(spec.symbol)
        conversationMenuItem.isEnabled = spec.isEnabled
        transcribeFileMenuItem?.isEnabled = MediaFileImport.isAvailable
    }

    // MARK: - Elapsed clocks

    private static var conversationElapsedSeconds: TimeInterval? {
        guard MeetingController.shared.state == .recording else { return nil }
        return MeetingController.shared.elapsed
    }

    private func startElapsedTicker() {
        stopElapsedTicker()
        // Either clock running is enough to keep the ticker alive.
        guard DictationController.shared.recordingElapsedSeconds != nil
                || Self.conversationElapsedSeconds != nil else { return }
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
        refreshStatusItem()
    }

    // MARK: - Actions

    @objc private func openHistory() {
        WindowOpener.shared.showMain(section: .history)
    }

    @objc private func openSettings() {
        WindowOpener.shared.showMain(section: .general)
    }

    @objc private func openUpdates() {
        WindowOpener.shared.showMain(section: .updates)
    }

    /// Opens Updates so the result has somewhere to show, and checks.
    @objc private func checkForUpdates() {
        WindowOpener.shared.showMain(section: .updates)
        Task { await AppUpdater.shared.checkForUpdate() }
    }

    /// The same text a History row's Copy puts on the pasteboard.
    @objc private func copyLastTranscript() {
        guard let entry = Self.lastTranscriptEntry else { return }
        let text = SpeakerRelabeler.apply(names: entry.speakerNames ?? [:], to: entry.transcript)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc private func openModels() {
        WindowOpener.shared.showMain(section: .models)
    }

    @objc private func openConversations() {
        WindowOpener.shared.showMain(section: .meetings)
    }

    @objc private func openStatusFix(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let section = SettingsView.Section(rawValue: raw) else { return }
        WindowOpener.shared.showMain(section: section)
    }

    /// The same call a row in the Models pane makes.
    @objc private func chooseModel(_ sender: NSMenuItem) {
        guard canChangeModel, let id = sender.representedObject as? String else { return }
        ModelRegistry.shared.setActive(id)
    }

    @objc private func toggleDictation() {
        DictationController.shared.toggle()
    }

    @objc private func toggleConversation() {
        MeetingController.shared.handleHotkeyPress()
    }

    @objc private func transcribeFile() {
        // Off the menu's own dispatch, so the modal panel doesn't run inside
        // the tail of menu tracking.
        Task { @MainActor in MediaFileImport.chooseAndImport(revealsFailure: true) }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// The menu's first line: the app's state ("● Ready", "● Recording 0:42") at
/// full contrast. A plain label in a view, inset to line up with the item
/// titles below it, and never highlighted — it isn't a command.
private final class MenuStatusView: NSView {
    /// Where AppKit starts a menu item's title.
    private static let titleInset: CGFloat = 16
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        autoresizingMask = [.width]
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.titleInset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.titleInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(_ text: NSAttributedString, spoken: String) {
        label.attributedStringValue = text
        label.setAccessibilityLabel(spoken)
    }
}

/// The status item's symbol layer. `NSImageView` is an `NSControl`, so an
/// untouched instance sitting on top of `NSStatusBarButton` would swallow the
/// click that opens the menu — this one is transparent to hit-testing, leaving
/// the button the only thing the pointer can reach.
private final class GlyphView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A global shortcut spelled as an `NSMenuItem` key equivalent, for display
/// beside the command it triggers. Nil for a key with no key-equivalent form.
private struct MenuShortcut {
    let key: String
    let modifiers: NSEvent.ModifierFlags

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = modifiers
    }

    init?(_ binding: HotkeyBinding) {
        guard let key = Self.key(for: binding) else { return nil }
        self.key = key
        var modifiers: NSEvent.ModifierFlags = []
        if binding.modifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if binding.modifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if binding.modifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if binding.modifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        self.modifiers = modifiers
    }

    private static func key(for binding: HotkeyBinding) -> String? {
        if let special = specialKeys[Int(binding.keyCode)] { return special }
        // A keypad key would print as its main-row twin, which the open menu
        // would then answer to; no key equivalent can name the keypad.
        guard !keypadKeyCodes.contains(Int(binding.keyCode)) else { return nil }
        // A character key: its label is the unshifted character, uppercased.
        guard binding.keyLabel.count == 1 else { return nil }
        return binding.keyLabel.lowercased()
    }

    private static let keypadKeyCodes: Set<Int> = [
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
        kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
        kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadClear,
        kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals,
    ]

    private static func functionKey(_ value: Int) -> String {
        UnicodeScalar(UInt32(value)).map { String(Character($0)) } ?? ""
    }

    private static let specialKeys: [Int: String] = {
        var keys: [Int: String] = [
            // AppKit draws " " as "Space", the word the keycaps use too.
            kVK_Space: " ",
            kVK_Return: "\r",
            kVK_Tab: "\t",
            kVK_Escape: "\u{1b}",
            kVK_Delete: "\u{8}",
            kVK_ForwardDelete: functionKey(NSDeleteFunctionKey),
            kVK_Home: functionKey(NSHomeFunctionKey),
            kVK_End: functionKey(NSEndFunctionKey),
            kVK_PageUp: functionKey(NSPageUpFunctionKey),
            kVK_PageDown: functionKey(NSPageDownFunctionKey),
            kVK_LeftArrow: functionKey(NSLeftArrowFunctionKey),
            kVK_RightArrow: functionKey(NSRightArrowFunctionKey),
            kVK_UpArrow: functionKey(NSUpArrowFunctionKey),
            kVK_DownArrow: functionKey(NSDownArrowFunctionKey),
        ]
        let functionKeyCodes = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, code) in functionKeyCodes.enumerated() {
            keys[code] = functionKey(NSF1FunctionKey + index)
        }
        return keys
    }()
}
