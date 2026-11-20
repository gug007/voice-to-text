import SwiftUI

/// Settings pane for corrections: the names and terms an engine keeps getting
/// wrong, and what to write instead. Most are remembered from fixes on the
/// review card, when the user says yes to the card's offer
/// (`TermCorrectionLearner`); this is where they are checked, changed,
/// removed, and added by hand.
struct CorrectionsPane: View {
    @Bindable private var store = TermCorrectionStore.shared

    @State private var editorDraft: CorrectionDraft?
    @State private var pendingUndo: PendingUndo?

    var body: some View {
        PaneScaffold {
            SettingsGroup {
                SettingsRow(
                    "Learn from my edits",
                    caption: "Fix a name or a term on the review card and VoiceToText offers to remember it.",
                    isOn: $store.learnsFromEdits
                )
            }

            SettingsGroup(
                "Your Corrections",
                footer: "Made in every new transcript, dictation and conversations alike. A correction matches whole words, in any case."
            ) {
                correctionRows
                addRow
            }
        }
        .overlay { UndoRemovalBar(pending: $pendingUndo) }
        .onDisappear { pendingUndo = nil }
        .sheet(item: $editorDraft) { draft in
            CorrectionEditorSheet(
                draft: draft,
                isTaken: { heard in
                    let key = TermCorrections.key(heard)
                    return store.corrections.contains { $0.id != draft.id && TermCorrections.key($0.heard) == key }
                },
                onSave: { heard, replacement in
                    store.save(heard: heard, replacement: replacement, id: draft.id)
                },
                onDelete: draft.isNew ? nil : {
                    if let correction = store.corrections.first(where: { $0.id == draft.id }) {
                        delete(correction)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var correctionRows: some View {
        if store.corrections.isEmpty {
            SettingsRow(
                "No corrections yet",
                caption: "Fix a name on the review card, or add one here."
            )
        } else {
            ForEach(store.corrections) { correction in
                correctionRow(correction)
            }
        }
    }

    private func correctionRow(_ correction: TermCorrection) -> some View {
        HStack(alignment: .center, spacing: Space.s5) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                Text(correction.heard)
                    .typo(.body)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                    .accessibilityHidden(true)
                Text(correction.replacement)
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { edit(correction) }
            .focusable(interactions: .activate)
            .onKeyPress(keys: [.return, .space]) { _ in
                edit(correction)
                return .handled
            }
            .help("Edit this correction")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("“\(correction.heard)” becomes “\(correction.replacement)”")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { edit(correction) }
            .accessibilityHint("Opens the correction editor")

            if correction.isLearned {
                Text("Learned")
                    .typo(.caption)
                    .foregroundStyle(Palette.inkFaint)
                    .help("Learned from an edit on the review card")
            }

            Button("Edit…") { edit(correction) }
                .buttonTier(.secondary)
                .controlSize(.small)
                .accessibilityLabel("Edit the correction for \(correction.heard)")

            IconButton("trash", label: "Delete the correction for “\(correction.heard)”", role: .destructive) {
                delete(correction)
            }
        }
        .settingsRowPadding()
        .contextMenu {
            Button("Edit…") { edit(correction) }
            Divider()
            Button("Delete", role: .destructive) { delete(correction) }
        }
    }

    private var addRow: some View {
        SettingsAddRow(title: "Add Correction…", help: "Add a correction (⌘N)") {
            // ⌘N must not replace a draft that is already open.
            guard editorDraft == nil else { return }
            editorDraft = CorrectionDraft()
        }
    }

    private func edit(_ correction: TermCorrection) {
        editorDraft = CorrectionDraft(correction: correction)
    }

    /// No confirmation: a correction is two short phrases, and Undo has them.
    private func delete(_ correction: TermCorrection) {
        let previous = store.corrections
        store.remove(id: correction.id)
        pendingUndo = PendingUndo(title: "Correction deleted") {
            store.restore(previous)
        }
    }
}

/// Sheet payload: an existing correction (edit) or a fresh id (add).
private struct CorrectionDraft: Identifiable {
    let id: UUID
    let heard: String
    let replacement: String
    let isNew: Bool

    init() {
        id = UUID()
        heard = ""
        replacement = ""
        isNew = true
    }

    init(correction: TermCorrection) {
        id = correction.id
        heard = correction.heard
        replacement = correction.replacement
        isNew = false
    }
}

private struct CorrectionEditorSheet: View {
    let draft: CorrectionDraft
    /// Whether another correction already covers these words.
    let isTaken: (String) -> Bool
    let onSave: (_ heard: String, _ replacement: String) -> Void
    /// Nil for a new correction.
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var heard: String
    @State private var replacement: String
    @FocusState private var focus: Field?

    private enum Field { case heard, replacement }

    init(
        draft: CorrectionDraft,
        isTaken: @escaping (String) -> Bool,
        onSave: @escaping (_ heard: String, _ replacement: String) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.draft = draft
        self.isTaken = isTaken
        self.onSave = onSave
        self.onDelete = onDelete
        _heard = State(initialValue: draft.heard)
        _replacement = State(initialValue: draft.replacement)
    }

    private var candidate: TermCorrection {
        TermCorrection(id: draft.id, heard: heard, replacement: replacement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.isNew ? "New Correction" : "Edit Correction")
                .typo(.title)
                .foregroundStyle(Palette.ink)
                .padding(.bottom, Space.s6)

            VStack(alignment: .leading, spacing: Space.section) {
                LabelledField(
                    "When a transcript says",
                    caption: isTaken(heard)
                        ? "There is already a correction for these words. Saving replaces it."
                        : "One or more words, matched whole and in any case."
                ) {
                    field("What the transcript says", text: $heard, prompt: "e.g. cloud code", field: .heard)
                }
                LabelledField("Write", caption: "Written exactly as typed here.") {
                    field("What to write", text: $replacement, prompt: "e.g. Claude Code", field: .replacement)
                }
            }

            buttonRow
                .padding(.top, Space.s7)
        }
        .padding(Space.s7)
        .frame(width: 460, alignment: .topLeading)
        .presentationBackground(Palette.plate)
        .defaultFocus($focus, .heard)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, field: Field) -> some View {
        TextField(label, text: text, prompt: Text(prompt).foregroundStyle(Palette.inkFaint))
            .textFieldStyle(.plain)
            .font(Typo.body)
            .focused($focus, equals: field)
            .padding(.horizontal, Space.s4)
            .frame(height: 28)
            .framedTextField(isFocused: focus == field)
            .accessibilityLabel(label)
    }

    private var buttonRow: some View {
        HStack(spacing: Space.s5) {
            if let onDelete {
                Button("Delete Correction", role: .destructive) {
                    dismiss()
                    onDelete()
                }
                .buttonTier(.destructive)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonTier(.secondary)
                .keyboardShortcut(.cancelAction)
            Button(draft.isNew ? "Add Correction" : "Save") {
                onSave(heard, replacement)
                dismiss()
            }
            .buttonTier(.primary)
            .keyboardShortcut(.defaultAction)
            .disabled(!candidate.isUsable)
        }
    }
}
