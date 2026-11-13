import SwiftUI

/// A setting just removed and how to put it back. Whatever `undo` captures,
/// a key included, lives only as long as the toast.
struct PendingUndo: Identifiable {
    let id = UUID()
    let title: String
    let undo: @MainActor () -> Void
}

/// The Undo toast for a removal in a settings pane; clears `pending` once
/// `RecordingHistoryStore.undoGraceSeconds` pass.
struct UndoRemovalBar: View {
    @Binding var pending: PendingUndo?
    @State private var countdown: UndoCountdown?

    var body: some View {
        FloatingBottomBar(item: pending, animationValue: pending?.id) { current in
            UndoDeletionToast(title: current.title, countdown: countdown) {
                countdown?.cancel()
                pending = nil
                current.undo()
            }
        }
        .onChange(of: pending?.id, initial: true) { _, id in
            countdown?.cancel()
            guard let id else {
                countdown = nil
                return
            }
            let binding = $pending
            countdown = UndoCountdown(duration: RecordingHistoryStore.undoGraceSeconds) {
                if binding.wrappedValue?.id == id { binding.wrappedValue = nil }
            }
        }
        .onDisappear { countdown?.cancel() }
    }
}
