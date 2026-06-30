import SwiftUI

/// A minimal, iOS-style "Undo" toast shown briefly after a recording (or a Clear
/// All) is deleted. A floating material pill at the bottom of the History /
/// Conversations panes: a label and a single Undo action. Tapping Undo restores
/// the recording; otherwise the deletion commits when the store's grace window
/// elapses. There is no countdown chrome on purpose — the affordance stays calm
/// and unobtrusive, matching the panes' grouped-list aesthetic.
struct UndoDeletionToast: View {
    let title: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Button(action: onUndo) {
                Text("Undo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityLabel("Undo deletion")
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pending = store.pendingDeletion
        return ZStack {
            if let pending {
                UndoDeletionToast(title: Self.title(for: pending.entries)) {
                    store.undoPendingDeletion()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .transition(
                    reduceMotion
                    ? .opacity
                    : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(pending != nil)
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86),
            value: pending != nil
        )
    }

    /// The toast line, derived from what was deleted: a batch (Clear All) reads
    /// "All recordings deleted"; a single one names its kind.
    private static func title(for entries: [RecordingHistoryEntry]) -> String {
        guard entries.count == 1, let entry = entries.first else { return "All recordings deleted" }
        return (entry.source ?? .dictation) == .meeting ? "Conversation deleted" : "Recording deleted"
    }
}
