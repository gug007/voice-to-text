import SwiftUI
import UniformTypeIdentifiers

/// Settings pane for dictation actions: AI transforms the user can apply to
/// a transcript from the review card (translate, clean up, etc.). Manages the
/// feature toggle and the persisted action list in `ActionsStore`.
struct ActionsPane: View {
    @Bindable private var store = ActionsStore.shared
    @Bindable private var keyStore = OpenAIAPIKeyStore.shared
    @Bindable private var credit = CloudCreditStatus.shared
    var onShowCloudSettings: () -> Void = {}

    @State private var editorDraft: ActionEditorDraft?
    @State private var isShowingKeyEntry = false
    @State private var pendingUndo: PendingUndo?
    @State private var pendingDeletion: DictationAction?
    @State private var draggingID: UUID?
    @State private var dropSlot: ActionDropSlot?
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @Environment(\.motion) private var motion

    var body: some View {
        PaneScaffold {
            SettingsGroup {
                providerRow
            }

            SettingsGroup(
                "Your Actions",
                footer: "Enabled actions get ⌘1–⌘9 on the review card, top to bottom; turning one off renumbers the ones below it.",
                dividerInset: ActionRowMetrics.textInset
            ) {
                actionRows
                addRow
            } accessory: {
                // Column label over the switches, which end on the same edge.
                Text("On review card")
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
        }
        .animation(motion.layout, value: keyStore.hasKey)
        .overlay { UndoRemovalBar(pending: $pendingUndo) }
        .onDisappear {
            pendingUndo = nil
            draggingID = nil
            dropSlot = nil
        }
        .sheet(item: $editorDraft) { draft in
            ActionEditorSheet(
                draft: draft,
                shortcutNumber: { shortcutNumber(for: draft.id, enabled: $0) },
                onSave: { saved in
                    if store.actions.contains(where: { $0.id == saved.id }) {
                        store.update(saved)
                    } else {
                        store.add(saved)
                    }
                },
                onDelete: draft.isNew ? nil : {
                    if let action = store.actions.first(where: { $0.id == draft.id }) {
                        delete(action)
                    }
                }
            )
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { action in
            Button("Delete", role: .destructive) { delete(action) }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(ActionEditorSheet.deletionMessage(for: action.templateId))
        }
    }

    // MARK: - Delete

    /// Undo stays after the confirmation: a custom prompt exists nowhere else.
    private func delete(_ action: DictationAction) {
        guard let index = store.actions.firstIndex(where: { $0.id == action.id }) else { return }
        store.remove(id: action.id)
        pendingUndo = PendingUndo(title: "Action deleted") {
            store.restore(action, at: index)
        }
    }

    /// The ⌘ number `id` would have with `enabled` set, counting a new action
    /// as appended at the end.
    private func shortcutNumber(for id: UUID, enabled: Bool) -> Int? {
        guard enabled else { return nil }
        var actions = store.actions
        if let index = actions.firstIndex(where: { $0.id == id }) {
            actions[index].isEnabled = true
        } else {
            actions.append(DictationAction(id: id, name: "", prompt: "", isEnabled: true))
        }
        return ActionOrdering.shortcutNumbers(in: actions)[id]
    }

    // MARK: - Provider row

    /// Which model runs the actions and whether it can. The model is fixed in
    /// code (`ActionRunner.modelId`); the key is what the user manages.
    private var providerRow: some View {
        HStack(alignment: .center, spacing: Space.s5) {
            ProviderIconTile(symbol: CloudProvider.openAI.tileSymbol, tint: CloudProvider.openAI.tileTint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("OpenAI · \(ActionRunner.modelId)")
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                Text(keyStore.hasKey
                     ? "Running an action sends the transcript text to OpenAI."
                     : "Actions stay off until you add an OpenAI API key.")
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            providerStatus
                .fixedSize()
        }
        .settingsRowPadding()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var providerStatus: some View {
        if !keyStore.hasKey {
            Button("Add API Key…") { isShowingKeyEntry = true }
                .buttonTier(.primary)
                .popover(isPresented: $isShowingKeyEntry, arrowEdge: .bottom) {
                    keyEntryPopover
                }
        } else {
            HStack(spacing: Space.s5) {
                if credit.isOutOfCredit(.openAI) {
                    StatusLabel(level: .warning, text: FailureCardCopy.outOfCreditLabel)
                } else {
                    StatusLabel(level: .ready, text: "Connected")
                }
                Button("Manage Key") { onShowCloudSettings() }
                    .buttonTier(.secondary)
                    .controlSize(.small)
                    .help("Test, replace or remove the OpenAI key in Cloud")
            }
        }
    }

    private var keyEntryPopover: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Text("OpenAI API key")
                .typo(.headline)
                .foregroundStyle(Palette.ink)

            APIKeyEntryView(config: .openAI, onConnected: {
                isShowingKeyEntry = false
            })

            Button("All Cloud Settings…") {
                isShowingKeyEntry = false
                onShowCloudSettings()
            }
            .buttonStyle(TextLinkButtonStyle(font: Typo.caption))
        }
        .padding(Space.s6)
        .frame(width: 380)
    }

    // MARK: - Action list

    /// The list's own last row, as in the system's editable lists.
    private var addRow: some View {
        HStack {
            Button {
                // ⌘N must not replace a draft that is already open.
                guard editorDraft == nil, !isShowingKeyEntry else { return }
                editorDraft = ActionEditorDraft()
            } label: {
                Label("Add Action…", systemImage: "plus")
            }
            .buttonTier(.secondary)
            .controlSize(.small)
            .keyboardShortcut("n", modifiers: .command)
            .help("Add an action (⌘N)")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FormMetrics.rowHorizontalPadding)
        .padding(.vertical, Space.s5)
    }

    @ViewBuilder
    private var actionRows: some View {
        if store.actions.isEmpty {
            SettingsRow("No actions yet", caption: "Add one to show it as a button on the review card.")
        } else {
            let actions = store.actions
            let shortcutNumbers = ActionOrdering.shortcutNumbers(in: actions)
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                reorderableRow(
                    action,
                    canMoveUp: index > 0,
                    canMoveDown: index < actions.count - 1,
                    shortcutNumber: shortcutNumbers[action.id]
                )
            }
        }
    }

    // MARK: - Reordering

    /// A row that drags to reorder, with its Move Up / Move Down, and the drop
    /// slot a drag over it proposes, drawn as a line on the edge above or
    /// below it.
    private func reorderableRow(
        _ action: DictationAction,
        canMoveUp: Bool,
        canMoveDown: Bool,
        shortcutNumber: Int?
    ) -> some View {
        actionRow(action, canMoveUp: canMoveUp, canMoveDown: canMoveDown, shortcutNumber: shortcutNumber)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            rowHeights[action.id] = $0
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
        .overlay(alignment: dropSlot?.after == true ? .bottom : .top) {
            if dropSlot?.targetID == action.id {
                Capsule()
                    .fill(Palette.accent)
                    .frame(height: 2)
                    .padding(.horizontal, FormMetrics.rowHorizontalPadding)
                    .offset(y: dropSlot?.after == true ? 1 : -1)
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
            rowMenuItems(action, canMoveUp: canMoveUp, canMoveDown: canMoveDown)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(action.name)
        .accessibilityActions {
            Button("Edit") { edit(action) }
            if canMoveUp {
                Button("Move Up") { store.moveUp(id: action.id) }
            }
            if canMoveDown {
                Button("Move Down") { store.moveDown(id: action.id) }
            }
        }
    }

    /// The row ⋯ menu and its context menu.
    @ViewBuilder
    private func rowMenuItems(_ action: DictationAction, canMoveUp: Bool, canMoveDown: Bool) -> some View {
        Button("Edit…") { edit(action) }
        Divider()
        Button("Move Up") { store.moveUp(id: action.id) }
            .disabled(!canMoveUp)
        Button("Move Down") { store.moveDown(id: action.id) }
            .disabled(!canMoveDown)
        Divider()
        Button("Delete…", role: .destructive) { pendingDeletion = action }
    }

    private func edit(_ action: DictationAction) {
        editorDraft = ActionEditorDraft(action: action)
    }

    private func actionRow(
        _ action: DictationAction,
        canMoveUp: Bool,
        canMoveDown: Bool,
        shortcutNumber: Int?
    ) -> some View {
        HStack(alignment: .center, spacing: Space.s5) {
            grip(action)

            // The name and summary are also an edit target: click, or focus
            // and press Return. ⌥⌘↑ / ⌥⌘↓ move the focused action.
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s3) {
                    Text(action.name)
                        .typo(.headline)
                        .foregroundStyle(action.isEnabled ? Palette.ink : Palette.inkMuted)
                        .lineLimit(1)
                    if let shortcutNumber {
                        Keycap(keys: ["⌘", "\(shortcutNumber)"], size: .small)
                            .help("⌘\(shortcutNumber) runs this action on the review card")
                    }
                }
                Text(ActionSummary.line(for: action))
                    .typo(.caption)
                    .foregroundStyle(action.isEnabled ? Palette.inkMuted : Palette.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { edit(action) }
            .focusable(interactions: .activate)
            .onKeyPress(keys: [.return, .space]) { _ in
                edit(action)
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                guard press.modifiers.contains(.command), press.modifiers.contains(.option) else { return .ignored }
                if press.key == .upArrow { store.moveUp(id: action.id) } else { store.moveDown(id: action.id) }
                return .handled
            }
            .help("Edit “\(action.name)”. With it focused, ⌥⌘↑ and ⌥⌘↓ move it.")
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { edit(action) }
            .accessibilityHint("Opens the action editor")

            Button("Edit…") { edit(action) }
                .buttonTier(.secondary)
                .controlSize(.small)
                .accessibilityLabel("Edit \(action.name)")

            IconMenu(label: "Move or delete \(action.name)") {
                rowMenuItems(action, canMoveUp: canMoveUp, canMoveDown: canMoveDown)
            }

            Toggle("Show \(action.name) on the review card", isOn: enabledBinding(for: action))
                .labelsHidden()
                .toggleStyle(.switch)
                .help(action.isEnabled
                      ? "On the review card. Turn off to hide it."
                      : "Not on the review card. Turn on to show it.")
        }
        .settingsRowPadding()
    }

    /// The leading handle. The whole row drags; the grip is what says so.
    private func grip(_ action: DictationAction) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.inkFaint)
            .frame(width: ActionRowMetrics.gripWidth)
            .padding(.trailing, -Space.s2)
            .help("Drag to reorder")
            .accessibilityLabel("Reorder \(action.name)")
            .accessibilityHint("Use the Move Up and Move Down actions.")
    }

    private func enabledBinding(for action: DictationAction) -> Binding<Bool> {
        Binding(
            get: { store.actions.first(where: { $0.id == action.id })?.isEnabled ?? false },
            set: { store.setEnabled($0, id: action.id) }
        )
    }
}

private enum ActionRowMetrics {
    static let gripWidth: CGFloat = 14
    /// Where the action name starts, for the hairlines between rows.
    static let textInset = FormMetrics.rowHorizontalPadding + gripWidth + Space.s5 - Space.s2
}

/// One line that tells actions apart: a plain summary for the built-ins the
/// user hasn't edited, otherwise the instruction's first sentence.
private enum ActionSummary {
    private static let builtIn: [String: String] = [
        "clean-transcript": "Clear, concise rewrite in the same language, without filler words.",
        "to-english": "Translates into natural, fluent English.",
        "improve-prompt": "Turns what you said into a clear, structured prompt for an AI assistant.",
        "fix-grammar": "Fixes grammar, spelling and punctuation; keeps your wording.",
        "summarize": "Sums up the text in one or two sentences.",
        "essentials-only": "Cuts the text down to its essential points.",
    ]

    static func line(for action: DictationAction) -> String {
        if let templateId = action.templateId,
           let template = ActionCatalog.defaults.first(where: { $0.id == templateId }),
           action.prompt == template.prompt,
           let summary = builtIn[templateId] {
            return summary
        }
        return firstSentence(of: action.prompt)
    }

    /// Abbreviations whose full stop doesn't end a sentence.
    private static let abbreviations: Set<String> = ["e.g.", "i.e.", "etc.", "vs.", "mr.", "mrs.", "ms.", "dr."]
    private static let closers: Set<Character> = ["\"", "”", "’", "'", ")"]

    /// Up to the earliest sentence end: ". ", "! " or "? ", also behind a
    /// closing quote or bracket. Abbreviations ("(e.g.") and list numbers
    /// ("1.") don't count.
    static func firstSentence(of text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        var index = flat.startIndex
        while index < flat.endIndex {
            defer { index = flat.index(after: index) }
            guard ".!?".contains(flat[index]) else { continue }
            var end = flat.index(after: index)
            while end < flat.endIndex, closers.contains(flat[end]) {
                end = flat.index(after: end)
            }
            guard end < flat.endIndex, flat[end] == " " else { continue }
            let word = flat[..<flat.index(after: index)]
                .split(separator: " ").last
                .map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "(\"“‘'")) } ?? ""
            if flat[index] == ".", abbreviations.contains(word) || word.dropLast().allSatisfy(\.isNumber) {
                continue
            }
            return String(flat[..<end])
        }
        return flat
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
    /// The built-in template this action came from, for Restore Default.
    let template: ActionCatalog.Template?

    init() {
        self.id = UUID()
        self.name = ""
        self.prompt = ""
        // Hand-written actions are an explicit opt-in, unlike seeded defaults.
        self.isEnabled = true
        self.isNew = true
        self.template = nil
    }

    init(action: DictationAction) {
        self.id = action.id
        self.name = action.name
        self.prompt = action.prompt
        self.isEnabled = action.isEnabled
        self.isNew = false
        self.template = action.templateId.flatMap { id in
            ActionCatalog.defaults.first { $0.id == id }
        }
    }
}

private struct ActionEditorSheet: View {
    let draft: ActionEditorDraft
    /// The ⌘ number the action gets on the review card with the given
    /// enabled state; nil when it gets none.
    let shortcutNumber: (Bool) -> Int?
    let onSave: (DictationAction) -> Void
    /// Nil for a new action.
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var prompt: String
    @State private var isEnabled: Bool
    @State private var isConfirmingDelete = false
    /// The instruction's laid-out text height, which sizes its box.
    @State private var promptTextHeight: CGFloat = 0
    @FocusState private var focus: Field?

    private enum Field { case name, prompt }

    init(
        draft: ActionEditorDraft,
        shortcutNumber: @escaping (Bool) -> Int?,
        onSave: @escaping (DictationAction) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.draft = draft
        self.shortcutNumber = shortcutNumber
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: draft.name)
        _prompt = State(initialValue: draft.prompt)
        _isEnabled = State(initialValue: draft.isEnabled)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The built-in template, only while the fields differ from it.
    private var changedTemplate: ActionCatalog.Template? {
        guard let template = draft.template,
              name != template.name || prompt != template.prompt else { return nil }
        return template
    }

    static func deletionMessage(for templateId: String?) -> String {
        templateId == nil
            ? "Its instruction is deleted too. You can undo for a few seconds."
            : "This built-in action won't come back on its own. You can undo for a few seconds."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.isNew ? "New Action" : "Edit Action")
                .typo(.title)
                .foregroundStyle(Palette.ink)
                .padding(.bottom, Space.s6)

            VStack(alignment: .leading, spacing: Space.section) {
                labelled("Name") {
                    TextField("Name", text: $name, prompt: Text("e.g. Translate to Spanish").foregroundStyle(Palette.inkFaint))
                        .textFieldStyle(.plain)
                        .font(Typo.body)
                        .focused($focus, equals: .name)
                        .padding(.horizontal, Space.s4)
                        .frame(height: 28)
                        .framedTextField(isFocused: focus == .name)
                }

                labelled("Instruction", caption: "Plain-language instruction, sent to OpenAI (\(ActionRunner.modelId)) with the transcript.") {
                    instructionEditor
                }

                reviewCardRow
                    .padding(.top, -Space.s3)
            }

            buttonRow
                .padding(.top, Space.s7)
        }
        .padding(Space.s7)
        .frame(minWidth: 560, idealWidth: 560, maxWidth: 900, minHeight: 360, maxHeight: .infinity, alignment: .topLeading)
        .presentationSizing(.fitted)
        .presentationBackground(Palette.plate)
        .defaultFocus($focus, .name)
        .confirmationDialog("Delete “\(draft.name)”?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                dismiss()
                onDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.deletionMessage(for: draft.template?.id))
        }
    }

    private func labelled<Content: View>(
        _ title: String,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title)
                .typo(.body)
                .foregroundStyle(Palette.inkMuted)
                .accessibilityAddTraits(.isHeader)
            content()
            if let caption {
                Text(caption)
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }

    /// Fits its text between 120 and 260pt, then scrolls. A hidden copy of
    /// the text, laid out at the editor's width, measures it.
    private var instructionEditor: some View {
        TextEditor(text: $prompt)
            .font(Typo.body)
            .lineSpacing(2)
            .scrollContentBackground(.hidden)
            .focused($focus, equals: .prompt)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, Space.s3)
            .frame(height: min(max(promptTextHeight + Space.s3 * 2 + 8, 120), 260))
            .background(alignment: .topLeading) {
                Text(prompt + "\n")
                    .font(Typo.body)
                    .lineSpacing(2)
                    .padding(.horizontal, Space.s2 + 5)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        promptTextHeight = $0
                    }
            }
            .overlay(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Tell the AI how to change the transcript, e.g. “Translate into Spanish and keep the tone.”")
                        .typo(.body)
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.horizontal, Space.s2 + 5)
                        .padding(.vertical, Space.s3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .framedTextField(isFocused: focus == .prompt)
            .accessibilityLabel("Instruction")
    }

    /// The same switch as the list row, with the shortcut it implies. The
    /// number is read-only: it is the action's place among the enabled ones.
    private var reviewCardRow: some View {
        HStack(alignment: .center, spacing: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Show on the review card")
                    .typo(.body)
                    .foregroundStyle(Palette.ink)
                shortcutHint
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Toggle("Show on the review card", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    @ViewBuilder
    private var shortcutHint: some View {
        if !isEnabled {
            hintText("Off: not on the review card, so no shortcut.")
        } else if let number = shortcutNumber(true) {
            HStack(spacing: Space.s2) {
                hintText("Shortcut")
                Keycap(keys: ["⌘", "\(number)"], size: .small)
                hintText("· set by its place in the list")
            }
        } else {
            hintText("No shortcut: only the first nine enabled actions get one.")
        }
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .typo(.caption)
            .foregroundStyle(Palette.inkMuted)
    }

    private var buttonRow: some View {
        HStack(spacing: Space.s5) {
            if onDelete != nil {
                Button("Delete Action…", role: .destructive) {
                    isConfirmingDelete = true
                }
                .buttonTier(.destructive)
            }
            if let template = changedTemplate {
                Button("Restore Default") {
                    name = template.name
                    prompt = template.prompt
                }
                .buttonTier(.secondary)
                .help("Put back the built-in name and instruction")
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonTier(.secondary)
                .keyboardShortcut(.cancelAction)
            Button(draft.isNew ? "Add Action" : "Save") {
                onSave(DictationAction(
                    id: draft.id,
                    name: trimmedName,
                    prompt: trimmedPrompt,
                    isEnabled: isEnabled
                ))
                dismiss()
            }
            .buttonTier(.primary)
            .keyboardShortcut(.defaultAction)
            .disabled(trimmedName.isEmpty || trimmedPrompt.isEmpty)
        }
    }
}
