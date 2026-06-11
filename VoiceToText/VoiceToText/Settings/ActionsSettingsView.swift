import SwiftUI

/// Settings pane for dictation actions: AI transforms the user can apply to
/// a transcript from the review HUD (translate, clean up, etc.). Manages the
/// feature toggle and the persisted action list in `ActionsStore`.
struct ActionsPane: View {
    @Bindable private var store = ActionsStore.shared
    @Bindable private var keyStore = OpenAIAPIKeyStore.shared
    var onShowCloudSettings: () -> Void = {}

    @State private var editorDraft: ActionEditorDraft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(
                    title: "Actions",
                    subtitle: "One-click AI edits for your transcript — enabled actions show as buttons in the review panel."
                )

                if !keyStore.hasKey {
                    missingKeyBanner
                }

                actionList

                addRow

                Text("Actions send the transcript to OpenAI (\(ActionRunner.modelId)). In the review panel, click an action or press ⌘1–⌘9.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(32)
            .animation(.easeInOut(duration: 0.18), value: keyStore.hasKey)
        }
        .sheet(item: $editorDraft) { draft in
            ActionEditorSheet(draft: draft) { saved in
                if store.actions.contains(where: { $0.id == saved.id }) {
                    store.update(saved)
                } else {
                    store.add(saved)
                }
            }
        }
    }

    // MARK: - Missing key banner

    /// Shown while no OpenAI key is configured — actions can't run without
    /// one. A quiet tinted banner instead of an alert: informative, one
    /// action, and it disappears on its own once a key is saved.
    private var missingKeyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenAI API key required")
                    .font(.system(size: 13, weight: .medium))
                Text("Actions run on the OpenAI API and stay inactive until a key is added.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Add Key…") {
                onShowCloudSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25))
        )
        .transition(.opacity)
    }

    // MARK: - Action list

    @ViewBuilder
    private var actionList: some View {
        if store.actions.isEmpty {
            Text("No actions yet. Add one below, or pick a suggestion.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 8) {
                ForEach(store.actions) { action in
                    actionRow(action, enabledIndex: enabledIndex(of: action))
                }
            }
        }
    }

    /// Position of the action among the *enabled* ones — that's the order
    /// the review-panel chips use, so the ⌘-shortcut hints must match it.
    private func enabledIndex(of action: DictationAction) -> Int? {
        guard action.isEnabled else { return nil }
        return store.enabledActions.firstIndex { $0.id == action.id }
    }

    private func actionRow(_ action: DictationAction, enabledIndex: Int?) -> some View {
        RowCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.name)
                        .font(.system(size: 14, weight: .medium))
                    Text(action.prompt)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(action.isEnabled ? 1.0 : 0.5)
                Spacer(minLength: 12)
                if let enabledIndex, enabledIndex < 9 {
                    Text("⌘\(enabledIndex + 1)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Button {
                    editorDraft = ActionEditorDraft(action: action)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit action")
                Button {
                    store.remove(id: action.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete action")
                Toggle("", isOn: enabledBinding(for: action))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(action.isEnabled ? "Hide from the review panel" : "Show in the review panel")
            }
            .padding(18)
        }
    }

    private func enabledBinding(for action: DictationAction) -> Binding<Bool> {
        Binding(
            get: { store.actions.first(where: { $0.id == action.id })?.isEnabled ?? false },
            set: { store.setEnabled($0, id: action.id) }
        )
    }

    private var addRow: some View {
        Button {
            editorDraft = ActionEditorDraft()
        } label: {
            Label("Add Action", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

/// Sheet payload: carries either an existing action (edit) or a fresh id (add).
private struct ActionEditorDraft: Identifiable {
    let id: UUID
    let name: String
    let prompt: String
    let isEnabled: Bool
    let isNew: Bool

    init() {
        self.id = UUID()
        self.name = ""
        self.prompt = ""
        // Hand-written actions are an explicit opt-in, unlike seeded defaults.
        self.isEnabled = true
        self.isNew = true
    }

    init(action: DictationAction) {
        self.id = action.id
        self.name = action.name
        self.prompt = action.prompt
        self.isEnabled = action.isEnabled
        self.isNew = false
    }
}

private struct ActionEditorSheet: View {
    let draft: ActionEditorDraft
    let onSave: (DictationAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var prompt: String

    init(draft: ActionEditorDraft, onSave: @escaping (DictationAction) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _name = State(initialValue: draft.name)
        _prompt = State(initialValue: draft.prompt)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.isNew ? "New Action" : "Edit Action")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. Translate to English", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Instruction")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $prompt)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 110)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                Text("Tell the AI how to transform the transcript.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.isNew ? "Add" : "Save") {
                    onSave(DictationAction(
                        id: draft.id,
                        name: trimmedName,
                        prompt: trimmedPrompt,
                        isEnabled: draft.isEnabled
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || trimmedPrompt.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
