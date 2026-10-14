import AppKit

// MARK: - Panel placement
//
// Where a HUD panel sits and how big it is: card size → panel frame, the
// remembered per-display position, dragging, and the morph clock the frame
// travels on. One per panel. The dictation card anchors by its bottom edge,
// the conversation card by its top, and each remembers its own positions —
// otherwise the two would share one spot and stack on top of each other.

@MainActor
final class HUDPanelPlacement {
    /// The card edge that holds still while the card resizes, and that the
    /// stored position measures. Growth happens away from it.
    enum AnchoredEdge {
        /// Grows upward — the dictation card, near the bottom of the screen.
        case bottom
        /// Grows downward — the conversation card, under the menu bar.
        case top
    }

    private weak var panel: NSPanel?
    private let edge: AnchoredEdge
    private let anchorsDefaultsKey: String
    /// The anchor before the user drags the card anywhere, from the screen's
    /// visible frame.
    private let defaultAnchor: (NSRect) -> NSPoint

    /// Last card size SwiftUI actually laid out. The panel frame is always this
    /// plus the shadow gutter — there are no `NSSize` constants left.
    private(set) var measuredCardSize: CGSize = .zero
    /// When the current morph ends. Late size corrections inside this window
    /// ride the same spring; after it they snap.
    private var morphDeadline: Date = .distantPast

    private var dragStartPanelOrigin: NSPoint?
    private var dragStartMouse: NSPoint?

    init(edge: AnchoredEdge, anchorsDefaultsKey: String, defaultAnchor: @escaping (NSRect) -> NSPoint) {
        self.edge = edge
        self.anchorsDefaultsKey = anchorsDefaultsKey
        self.defaultAnchor = defaultAnchor
    }

    func attach(_ panel: NSPanel) {
        self.panel = panel
    }

    // MARK: Frame

    /// The card is about to lay out at `cardSize`. Remembered first, so the
    /// size SwiftUI reports back matches instead of triggering a correction;
    /// `animated` opens the morph window the frame and the card share.
    func expect(cardSize: CGSize, animated: Bool) {
        if animated { morphDeadline = Date().addingTimeInterval(HUDMetrics.morphDuration) }
        measuredCardSize = cardSize
    }

    /// The panel went away. Nothing that arrives after this may ride a morph
    /// that ended with it.
    func panelHidden() {
        morphDeadline = .distantPast
    }

    /// Called by the card once SwiftUI has laid it out. The estimate the panel
    /// passed to `expect` is exact for every fixed-height section, so this only
    /// fires when content actually grew — a two-line failure banner, a
    /// localized button that widened the control row.
    func cardSizeChanged(_ size: CGSize) {
        let rounded = CGSize(width: size.width.rounded(), height: size.height.rounded())
        guard rounded.width > 1, rounded.height > 1 else { return }
        guard abs(rounded.width - measuredCardSize.width) > 0.5
                || abs(rounded.height - measuredCardSize.height) > 0.5 else { return }
        measuredCardSize = rounded

        let animated = HUDFeatureFlags.morphEnabled && Date() < morphDeadline
        // Deferred one turn: this arrives from inside SwiftUI's layout pass and
        // resizing the window synchronously from there re-enters it.
        Task { @MainActor [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.applyFrame(cardSize: rounded, animated: animated)
        }
    }

    func applyFrame(cardSize: CGSize, animated: Bool) {
        guard let panel else { return }
        let frame = panelFrame(cardSize: cardSize)
        guard frame != panel.frame else { return }

        guard animated else {
            panel.setFrame(frame, display: true, animate: false)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = HUDMetrics.morphDuration
            context.timingFunction = HUDMetrics.morphTiming
            // Lets the layer-backed content ride the same clock as the frame.
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Panel frame = card + an 88pt transparent shadow gutter on every side,
    /// anchored by the *card's* anchored edge and horizontal centre so growth
    /// happens away from that edge and outward from where the user last put it.
    ///
    /// Every coordinate here is card space — the anchor is on the card's edge,
    /// the clamp keeps the card on screen, and the gutter is added back only at
    /// the end. Measuring on the panel instead would tie a persisted position to
    /// `gutter`, so changing the shadow's size would silently move every HUD
    /// anyone had ever dragged.
    private func panelFrame(cardSize: CGSize) -> NSRect {
        let size = NSSize(
            width: cardSize.width + HUDMetrics.gutter * 2,
            height: cardSize.height + HUDMetrics.gutter * 2
        )
        let screen = activeScreen()
        let visible = screen.visibleFrame
        let anchor = anchor(on: screen)

        let cardX = Self.clamp(
            (anchor.x - cardSize.width / 2).rounded(),
            visible.minX + HUDMetrics.screenMargin,
            visible.maxX - cardSize.width - HUDMetrics.screenMargin
        )
        let anchoredY = switch edge {
        case .bottom: anchor.y
        case .top: anchor.y - cardSize.height
        }
        let cardY = Self.clamp(
            anchoredY.rounded(),
            visible.minY + HUDMetrics.screenMargin,
            visible.maxY - cardSize.height - HUDMetrics.screenMargin
        )
        return NSRect(
            x: cardX - HUDMetrics.gutter,
            y: cardY - HUDMetrics.gutter,
            width: size.width,
            height: size.height
        )
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        guard high >= low else { return (low + high) / 2 }
        return min(max(value, low), high)
    }

    // MARK: Placement

    /// The screen the HUD belongs on: whatever screen it is already showing on
    /// (a morph must never teleport the card between displays), otherwise the
    /// screen holding the focused window of the frontmost app — which is where
    /// the user is working.
    private func activeScreen() -> NSScreen {
        if let panel, panel.isVisible, let screen = panel.screen { return screen }
        if let screen = Self.focusedWindowScreen() { return screen }
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) { return screen }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// The screen containing the frontmost window of the frontmost application.
    ///
    /// Read from the window server rather than the Accessibility API: bounds and
    /// owner PID are readable without Screen Recording permission (only window
    /// *names* are gated), and the list is already in front-to-back order.
    private static func focusedWindowScreen() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in infos {
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 64, h > 64
            else { continue }
            // CGWindow bounds are top-left origin, measured from the top of the
            // primary display; NSScreen is bottom-left origin.
            guard let primaryTop = NSScreen.screens.first?.frame.maxY else { return nil }
            let rect = NSRect(x: x, y: primaryTop - y - h, width: w, height: h)
            let centre = NSPoint(x: rect.midX, y: rect.midY)
            if let hit = NSScreen.screens.first(where: { NSMouseInRect(centre, $0.frame, false) }) {
                return hit
            }
            return NSScreen.screens.max { a, b in
                a.frame.intersection(rect).area < b.frame.intersection(rect).area
            }
        }
        return nil
    }

    /// The centre of the card's anchored edge in screen coordinates: the user's
    /// dragged position for this display, or the default.
    private func anchor(on screen: NSScreen) -> NSPoint {
        storedAnchor(on: screen) ?? defaultAnchor(screen.visibleFrame)
    }

    /// Per-display identity that survives a reconnect: the display's name plus
    /// its point size. `CGDirectDisplayID` is recycled across reconnects and
    /// `NSScreen.frame.origin` moves whenever the arrangement changes, so
    /// neither is usable as a key on its own.
    private static func screenKey(_ screen: NSScreen) -> String {
        let size = screen.frame.size
        return "\(screen.localizedName)|\(Int(size.width))x\(Int(size.height))"
    }

    private func storedAnchor(on screen: NSScreen) -> NSPoint? {
        let store = UserDefaults.standard.dictionary(forKey: anchorsDefaultsKey) as? [String: [Double]]
        guard let pair = store?[Self.screenKey(screen)], pair.count == 2 else { return nil }
        // Stored relative to the visible frame's origin so a rearranged desktop
        // keeps the HUD in the same place on this display rather than off it.
        let visible = screen.visibleFrame
        return NSPoint(x: visible.minX + pair[0], y: visible.minY + pair[1])
    }

    private func storeAnchor(_ point: NSPoint, on screen: NSScreen) {
        let visible = screen.visibleFrame
        var store = UserDefaults.standard.dictionary(forKey: anchorsDefaultsKey) as? [String: [Double]] ?? [:]
        store[Self.screenKey(screen)] = [point.x - visible.minX, point.y - visible.minY]
        UserDefaults.standard.set(store, forKey: anchorsDefaultsKey)
    }

    private func clearAnchor(on screen: NSScreen) {
        var store = UserDefaults.standard.dictionary(forKey: anchorsDefaultsKey) as? [String: [Double]] ?? [:]
        store.removeValue(forKey: Self.screenKey(screen))
        UserDefaults.standard.set(store, forKey: anchorsDefaultsKey)
    }

    // MARK: Dragging

    /// Screen-absolute drag: the window moves under the cursor, so a
    /// window-relative translation would chase itself and oscillate.
    func dragBegan() {
        dragStartPanelOrigin = panel?.frame.origin
        dragStartMouse = NSEvent.mouseLocation
    }

    func dragChanged() {
        guard let panel, let origin = dragStartPanelOrigin, let start = dragStartMouse else { return }
        let now = NSEvent.mouseLocation
        panel.setFrameOrigin(
            NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y)
        )
    }

    func dragEnded() {
        defer {
            dragStartPanelOrigin = nil
            dragStartMouse = nil
        }
        guard let panel, let screen = panel.screen else { return }
        let edgeY = switch edge {
        case .bottom: panel.frame.minY + HUDMetrics.gutter
        case .top: panel.frame.maxY - HUDMetrics.gutter
        }
        storeAnchor(NSPoint(x: panel.frame.midX, y: edgeY), on: screen)
    }

    /// Double-click on the card: forget this display's stored origin and spring
    /// back to the default position.
    func resetPosition() {
        guard let panel, let screen = panel.screen else { return }
        clearAnchor(on: screen)
        let animated = HUDFeatureFlags.morphEnabled
        if animated { morphDeadline = Date().addingTimeInterval(HUDMetrics.morphDuration) }
        applyFrame(cardSize: measuredCardSize, animated: animated)
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
