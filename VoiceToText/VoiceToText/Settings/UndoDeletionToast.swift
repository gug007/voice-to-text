import SwiftUI

/// A minimal, iOS-style "Undo" toast shown briefly after a recording (or a Clear
/// All) is deleted. A floating glass pill at the bottom of the History /
/// Conversations panes: a label and a single Undo action. Tapping Undo restores
/// the recording; otherwise the deletion commits when the store's grace window
/// elapses. The only countdown chrome is a small ring inside Undo that drains
/// over that window; the pointer on the toast holds it, and the commit with it.
///
/// This is glass surface #3 of the inventory in `GlassSurface.swift`. It used to
/// hand-roll its own `.regularMaterial` + stroke, which meant Reduce
/// Transparency flattened the HUD and left the toast translucent over it —
/// `glassSurface` owns both now, on every OS version and both accessibility
/// branches. Elevation stays here (see `reduceTransparency` below): the glass
/// modifier deliberately carries no shadow, because two of its four call sites
/// are popovers whose own window already draws one.
struct UndoDeletionToast: View {
    let title: String
    /// The window the deletion commits on, when the caller has one to show.
    var countdown: UndoCountdown?
    let onUndo: () -> Void

    /// L3 elevation is the one thing `glassSurface` does NOT own — it applies
    /// blur, hairline and the opaque fallback, and the HUD adds its own shadow
    /// on top of it for exactly the same reason. Without this the toast is the
    /// only floating surface in the app with no elevation on macOS 15, where the
    /// fallback is plain `.regularMaterial`, and it reads as part of the list it
    /// is supposed to be sitting above.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: Space.s5) {
            Image(systemName: "trash")
                .font(Typo.headline)
                .foregroundStyle(Palette.inkMuted)

            Text(title)
                .typo(.headline)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)

            Spacer(minLength: Space.s5)

            Button(action: onUndo) {
                HStack(spacing: Space.s3) {
                    if let countdown {
                        UndoCountdownRing(countdown: countdown)
                    }
                    Text("Undo")
                        .typo(.headline)
                }
                .foregroundStyle(Palette.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityLabel("Undo deletion")
        }
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s5)
        .glassSurface(in: Capsule())
        .floatingShadow(reduceTransparency: reduceTransparency)
        .frame(maxWidth: 460)
        .onHover { countdown?.setPaused($0) }
        // Taken away under the pointer, the toast never sees it leave.
        .onDisappear { countdown?.setPaused(false) }
        .onAppear { announce(title) }
    }

    /// Speak the toast for VoiceOver — an overlay insertion isn't reliably
    /// announced, and the toast must never be the only way to learn undo exists.
    private func announce(_ text: String) {
        var message = AttributedString(text + ". Undo available.")
        message.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(message).post()
    }
}

/// Bottom overlay that surfaces the store's current `pendingDeletion` as an
/// `UndoDeletionToast`. Drop it on a pane via `.overlay { UndoDeletionBar(store:) }`.
/// It fills the pane but only intercepts hits while a toast is showing, so it
/// never blocks the list underneath. Honors Reduce Motion.
struct UndoDeletionBar: View {
    let store: RecordingHistoryStore

    var body: some View {
        let pending = store.pendingDeletion
        return FloatingBottomBar(item: pending, animationValue: pending != nil) { pending in
            UndoDeletionToast(
                title: Self.title(for: pending),
                countdown: store.pendingDeletionCountdown
            ) {
                store.undoPendingDeletion()
            }
        }
    }

    /// The toast line, derived from what was deleted: Clear All reads "All
    /// recordings deleted", a selection is counted, and a single one names its
    /// kind.
    private static func title(for pending: RecordingHistoryStore.PendingDeletion) -> String {
        guard pending.entries.count == 1, let entry = pending.entries.first else {
            return pending.isClearAll
                ? "All recordings deleted"
                : HistorySelection.deletionTitle(count: pending.entries.count)
        }
        return (entry.source ?? .dictation) == .meeting ? "Conversation deleted" : "Recording deleted"
    }
}

/// The bottom-of-pane slot the Undo toasts and the History selection bar float
/// in. It fills the pane but only takes hits while something is showing, and
/// enters on the HUD's spring: both are L3 glass arriving over content, and
/// under Reduce Motion both collapse to the 0.15s fade.
struct FloatingBottomBar<Value: Equatable, Content: View>: View {
    private let content: Content?
    private let animationValue: Value
    @Environment(\.motion) private var motion

    init<Item>(item: Item?, animationValue: Value, @ViewBuilder content: (Item) -> Content) {
        self.content = item.map(content)
        self.animationValue = animationValue
    }

    init(isPresented: Bool, animationValue: Value, @ViewBuilder content: () -> Content) {
        self.content = isPresented ? content() : nil
        self.animationValue = animationValue
    }

    var body: some View {
        ZStack {
            if let content {
                content
                    .padding(.horizontal, Space.s7)
                    .padding(.bottom, Space.s7)
                    .transition(
                        motion.reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(content != nil)
        .animation(motion.hudEnter, value: animationValue)
    }
}
