import SwiftUI
import UniformTypeIdentifiers

/// Settings pane for dictation actions: AI transforms the user can apply to
/// a transcript from the review HUD (translate, clean up, etc.). Manages the
/// feature toggle and the persisted action list in `ActionsStore`.
struct ActionsPane: View {
    @Bindable private var store = ActionsStore.shared
    @Bindable private var keyStore = OpenAIAPIKeyStore.shared
    var onShowCloudSettings: () -> Void = {}

    @State private var editorDraft: ActionEditorDraft?
    @State private var isShowingKeyEntry = false
    @State private var pendingUndo: PendingUndo?
    @State private var draggingID: UUID?
    @State private var dropSlot: ActionDropSlot?
    @State private var rowHeights: [UUID: CGFloat] = [:]
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

            Text("Actions send the transcript to OpenAI (\(ActionRunner.modelId)). In the review panel, click an action or press ⌘1–⌘9, numbered in the order shown here. Drag an action by its handle to reorder.")
                .typo(.caption)
                .foregroundStyle(Palette.inkFaint)
        }
        .animation(motion.layout, value: keyStore.hasKey)
        .overlay { UndoRemovalBar(pending: $pendingUndo) }
        .onDisappear {
            pendingUndo = nil
            draggingID = nil
            dropSlot = nil
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

    // MARK: - Undo

    /// A slip on the trash icon shouldn't silently cost a custom prompt.
    private func delete(_ action: DictationAction) {
        guard let index = store.actions.firstIndex(where: { $0.id == action.id }) else { return }
        store.remove(id: action.id)
        pendingUndo = PendingUndo(title: "Action deleted") {
            store.restore(action, at: index)
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
                action: { isShowingKeyEntry = true }
            )
        ])
        .transition(.opacity)
        .popover(isPresented: $isShowingKeyEntry, arrowEdge: .bottom) {
            keyEntryPopover
        }
    }

    private var keyEntryPopover: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Text("OpenAI API key")
                .typo(.headline)
                .foregroundStyle(Palette.ink)

            APIKeyEntryView(config: .openAI) {
                isShowingKeyEntry = false
            }

            Button {
                isShowingKeyEntry = false
                onShowCloudSettings()
            } label: {
                Text("All cloud settings…")
                    .typo(.captionMedium)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent)
        }
        .padding(Space.s6)
        .frame(width: 380)
    }

    // MARK: - Action list

    @ViewBuilder
    private var actionList: some View {
        if store.actions.isEmpty {
            Text("No actions yet. Add one below, or pick a suggestion.")
                .typo(.body)
                .foregroundStyle(Palette.inkMuted)
        } else {
            let actions = store.actions
            let shortcutNumbers = ActionOrdering.shortcutNumbers(in: actions)
            VStack(spacing: Space.s4) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    reorderableRow(
                        action,
                        canMoveUp: index > 0,
                        canMoveDown: index < actions.count - 1,
                        shortcutNumber: shortcutNumbers[action.id]
                    )
                }
            }
            .animation(motion.layout, value: actions.map(\.id))
        }
    }

    // MARK: - Reordering

    /// A plate with its grip, its Move Up / Move Down, and the drop slot a
    /// drag over it proposes, drawn as a line in the gap above or below it.
    private func reorderableRow(
        _ action: DictationAction,
        canMoveUp: Bool,
        canMoveDown: Bool,
        shortcutNumber: Int?
    ) -> some View {
        actionRow(action, shortcutNumber: shortcutNumber)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            rowHeights[action.id] = $0
        }
        .overlay(alignment: dropSlot?.after == true ? .bottom : .top) {
            if dropSlot?.targetID == action.id {
                Capsule()
                    .fill(Palette.accent)
                    .frame(height: 2)
                    .offset(y: dropSlot?.after == true ? Space.s4 / 2 + 1 : -(Space.s4 / 2 + 1))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onDrop(of: [.text], delegate: ActionDropDelegate(
            targetID: action.id,
            rowHeight: rowHeights[action.id] ?? 0,
            draggingID: $draggingID,
            slot: $dropSlot,
            isMeaningful: { dragged, slot in
                ActionOrdering.reorders(dragged, besides: slot.targetID, after: slot.after, in: store.actions)
            },
            onMove: { dragged, slot in
                store.move(id: dragged, besides: slot.targetID, after: slot.after)
            }
        ))
        .contextMenu {
            Button("Move Up") { store.moveUp(id: action.id) }
                .disabled(!canMoveUp)
            Button("Move Down") { store.moveDown(id: action.id) }
                .disabled(!canMoveDown)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(action.name)
        .accessibilityActions {
            if canMoveUp {
                Button("Move Up") { store.moveUp(id: action.id) }
            }
            if canMoveDown {
                Button("Move Down") { store.moveDown(id: action.id) }
            }
        }
    }

    /// The leading handle a drag starts from. Focusable from the keyboard,
    /// where ↑ and ↓ move the action without dragging.
    private func grip(_ action: DictationAction) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(Typo.captionMedium)
            .foregroundStyle(Palette.inkFaint)
            .frame(width: 16, height: 24)
            .contentShape(Rectangle())
            .focusable(interactions: .activate)
            .onMoveCommand { direction in
                switch direction {
                case .up: store.moveUp(id: action.id)
                case .down: store.moveDown(id: action.id)
                default: break
                }
            }
            .onDrag {
                draggingID = action.id
                return NSItemProvider(object: action.id.uuidString as NSString)
            } preview: {
                Text(action.name)
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Space.s6)
                    .padding(.vertical, Space.s4)
                    .background(Capsule().fill(Palette.plate))
            }
            .help("Drag to reorder")
            .accessibilityLabel("Reorder \(action.name)")
            .accessibilityHint("Use the Move Up and Move Down actions.")
    }

    private func actionRow(_ action: DictationAction, shortcutNumber: Int?) -> some View {
        Plate {
            HStack(alignment: .center, spacing: Space.s6) {
                grip(action)
                    .padding(.trailing, -Space.s3)
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
                if let shortcutNumber {
                    Text("⌘\(shortcutNumber)")
                        .typo(.mono)
                        .foregroundStyle(Palette.inkFaint)
                }
                Button {
                    editorDraft = ActionEditorDraft(action: action)
                } label: {
                    Image(systemName: "pencil")
                        .font(Typo.body)
                        .foregroundStyle(Palette.inkMuted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit action")
                .accessibilityLabel("Edit \(action.name)")
                Button {
                    delete(action)
                } label: {
                    Image(systemName: "trash")
                        .font(Typo.captionMedium)
                        .foregroundStyle(Palette.inkMuted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete action")
                .accessibilityLabel("Delete \(action.name)")
                Toggle(action.name, isOn: enabledBinding(for: action))
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

/// Where a drag over the action list would land: just above or below a row.
private struct ActionDropSlot: Equatable {
    let targetID: UUID
    let after: Bool
}

/// One row's drop target. The top half of the plate proposes the slot above
/// it, the bottom half the slot below; a slot that would leave the order as
/// it is shows no line and drops as a no-op.
private struct ActionDropDelegate: DropDelegate {
    let targetID: UUID
    let rowHeight: CGFloat
    @Binding var draggingID: UUID?
    @Binding var slot: ActionDropSlot?
    let isMeaningful: (UUID, ActionDropSlot) -> Bool
    let onMove: (UUID, ActionDropSlot) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingID != nil
    }

    func dropEntered(info: DropInfo) {
        updateSlot(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateSlot(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if slot?.targetID == targetID { slot = nil }
    }

    /// Moves only the action this pane's drag carries: a drag released
    /// outside the list leaves `draggingID` behind, and any text dropped here
    /// later — from another app, say — must not move that action.
    func performDrop(info: DropInfo) -> Bool {
        let expected = draggingID
        let proposed = proposedSlot(info)
        slot = nil
        draggingID = nil
        guard let expected, let provider = info.itemProviders(for: [.text]).first else { return false }
        let onMove = onMove
        Task { @MainActor in
            guard await Self.droppedString(from: provider) == expected.uuidString else { return }
            onMove(expected, proposed)
        }
        return true
    }

    private static func droppedString(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: (object as? NSString).map { $0 as String })
            }
        }
    }

    private func proposedSlot(_ info: DropInfo) -> ActionDropSlot {
        ActionDropSlot(targetID: targetID, after: info.location.y > rowHeight / 2)
    }

    private func updateSlot(_ info: DropInfo) {
        guard let draggingID else { return }
        let proposed = proposedSlot(info)
        let next = isMeaningful(draggingID, proposed) ? proposed : nil
        if slot != next { slot = next }
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
                .buttonStyle(FilledButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || trimmedPrompt.isEmpty)
            }
        }
        .padding(Space.s7)
        .frame(width: 440)
    }
}
