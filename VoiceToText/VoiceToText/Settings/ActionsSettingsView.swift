import SwiftUI

/// Settings pane for dictation actions: AI transforms the user can apply to
/// a transcript from the review HUD (translate, clean up, etc.). Manages the
/// feature toggle and the persisted action list in `ActionsStore`.
struct ActionsPane: View {
    @Bindable private var store = ActionsStore.shared
    @Bindable private var keyStore = OpenAIAPIKeyStore.shared
    var onShowCloudSettings: () -> Void = {}

    @State private var editorDraft: ActionEditorDraft?
    @Environment(\.motion) private var motion

    var body: some View {
        PaneScaffold {
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
                .typo(.caption)
                .foregroundStyle(Palette.inkFaint)
        }
        .animation(motion.layout, value: keyStore.hasKey)
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
    /// one. The same status vocabulary the General pane's permission group
    /// uses: informative, one action, and it disappears on its own once a key
    /// is saved.
    private var missingKeyBanner: some View {
        StatusPlate([
            StatusItem(
                id: "openai-key",
                level: .warning,
                title: "OpenAI API key required",
                message: "Actions run on the OpenAI API and stay inactive until a key is added.",
                actionTitle: "Add Key…",
                action: onShowCloudSettings
            )
        ])
        .transition(.opacity)
    }

    // MARK: - Action list

    @ViewBuilder
    private var actionList: some View {
        if store.actions.isEmpty {
            Text("No actions yet. Add one below, or pick a suggestion.")
                .typo(.body)
                .foregroundStyle(Palette.inkMuted)
        } else {
            VStack(spacing: Space.s4) {
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
        Plate {
            HStack(alignment: .center, spacing: Space.s6) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(action.name)
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(action.prompt)
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(action.isEnabled ? 1.0 : 0.5)
                Spacer(minLength: Space.s5)
                if let enabledIndex, enabledIndex < 9 {
                    Text("⌘\(enabledIndex + 1)")
                        .typo(.mono)
                        .foregroundStyle(Palette.inkFaint)
                }
                Button {
                    editorDraft = ActionEditorDraft(action: action)
                } label: {
                    Image(systemName: "pencil")
                        .font(Typo.body)
                        .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.plain)
                .help("Edit action")
                Button {
                    store.remove(id: action.id)
                } label: {
                    Image(systemName: "trash")
                        .font(Typo.captionMedium)
                        .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.plain)
                .help("Delete action")
                Toggle("", isOn: enabledBinding(for: action))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(action.isEnabled ? "Hide from the review panel" : "Show in the review panel")
            }
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
        VStack(alignment: .leading, spacing: Space.s6) {
            Text(draft.isNew ? "New Action" : "Edit Action")
                .typo(.title)
                .foregroundStyle(Palette.ink)

            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Name")
                    .typo(.captionMedium)
                    .foregroundStyle(Palette.inkMuted)
                TextField("e.g. Translate to English", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Instruction")
                    .typo(.captionMedium)
                    .foregroundStyle(Palette.inkMuted)
                TextEditor(text: $prompt)
                    .font(Typo.body)
                    .scrollContentBackground(.hidden)
                    .padding(Space.s4)
                    .frame(height: 110)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Palette.wellFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Palette.hairline)
                    )
                Text("Tell the AI how to transform the transcript.")
                    .typo(.caption)
                    .foregroundStyle(Palette.inkFaint)
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
        .padding(Space.s7)
        .frame(width: 440)
    }
}
