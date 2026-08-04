import SwiftUI

/// A minimal, iOS-style "Undo" toast shown briefly after a recording (or a Clear
/// All) is deleted. A floating glass pill at the bottom of the History /
/// Conversations panes: a label and a single Undo action. Tapping Undo restores
/// the recording; otherwise the deletion commits when the store's grace window
/// elapses. There is no countdown chrome on purpose — the affordance stays calm
/// and unobtrusive, matching the panes' grouped-list aesthetic.
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
                Text("Undo")
                    .typo(.headline)
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
        // Spec L3: `0 16px 48px rgba(0,0,0,0.30)` — the same level the HUD card
        // carries, pulled in under Reduce Transparency exactly as `HUDElevation`
        // pulls its own in, so the two L3 surfaces stay a matched pair.
        .shadow(
            color: .black.opacity(reduceTransparency ? 0.24 : 0.30),
            radius: reduceTransparency ? 9 : 24,
            y: reduceTransparency ? 6 : 16
        )
        .frame(maxWidth: 460)
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
    /// The toast has always been the one surface in the app that honoured an
    /// accessibility setting. It still does — it just reads the resolved
    /// vocabulary now instead of re-deriving a spring from
    /// `accessibilityReduceMotion` by hand, so it can never drift from the HUD
    /// it shares an elevation level with.
    @Environment(\.motion) private var motion

    var body: some View {
        let pending = store.pendingDeletion
        return ZStack {
            if let pending {
                UndoDeletionToast(title: Self.title(for: pending.entries)) {
                    store.undoPendingDeletion()
                }
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
        .allowsHitTesting(pending != nil)
        // Same spring as the HUD's entrance: both are L3 glass arriving over
        // content, and under Reduce Motion both collapse to the 0.15s fade.
        .animation(motion.hudEnter, value: pending != nil)
    }

    /// The toast line, derived from what was deleted: a batch (Clear All) reads
    /// "All recordings deleted"; a single one names its kind.
    private static func title(for entries: [RecordingHistoryEntry]) -> String {
        guard entries.count == 1, let entry = entries.first else { return "All recordings deleted" }
        return (entry.source ?? .dictation) == .meeting ? "Conversation deleted" : "Recording deleted"
    }
}
