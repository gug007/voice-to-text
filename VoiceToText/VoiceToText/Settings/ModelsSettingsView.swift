import SwiftUI

// MARK: - The Models pane
//
// "In Use" assigns models: one picker each for dictation, conversations and the
// second shortcut. Below it the catalog, one table-like group per provider
// ("On this Mac", "OpenAI", "ElevenLabs", "Groq") with aligned columns for
// accuracy, speed, size or price and languages. Rows show which roles they
// fill; clicking one opens its details, and its ⋯ menu assigns, downloads or
// deletes.

struct ModelsPane: View {
    @Bindable var registry: ModelRegistry
    var onShowCloudSettings: () -> Void = {}
    @Environment(\.motion) private var motion
    @State private var scope: ModelScope = .all
    @State private var sort: ModelSort = .quality
    @Bindable private var credit = CloudCreditStatus.shared

    enum ModelScope: String, CaseIterable, Identifiable {
        case all, local, cloud
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All Models"
            case .local: return "On this Mac"
            case .cloud: return "Cloud"
            }
        }

        /// The groups this scope shows, in reading order. Empty ones are dropped.
        var groups: [ModelGroup] {
            switch self {
            case .all: return [.local, .openAI, .elevenLabs, .groq]
            case .local: return [.local]
            case .cloud: return [.openAI, .elevenLabs, .groq]
            }
        }
    }

    enum ModelSort: String, CaseIterable, Identifiable {
        case featured, quality, speed, name
        var id: String { rawValue }

        var title: String {
            switch self {
            case .featured: return "Featured"
            case .quality: return "Accuracy"
            case .speed: return "Speed"
            case .name: return "Name"
            }
        }
    }

    /// Sorting runs within a group, never across groups.
    private func models(in group: ModelGroup) -> [ModelDescriptor] {
        sorted(ModelCatalog.all.filter(group.contains))
    }

    private var visibleGroups: [ModelGroup] {
        scope.groups.filter { !models(in: $0).isEmpty }
    }

    /// `sorted(by:)` is stable, so ties keep their curated catalog order.
    private func sorted(_ models: [ModelDescriptor]) -> [ModelDescriptor] {
        switch sort {
        case .featured:
            return models
        case .quality:
            return models.sorted { ($0.quality ?? -1) > ($1.quality ?? -1) }
        case .speed:
            return models.sorted { $0.speed > $1.speed }
        case .name:
            return models.sorted {
                $0.sectionedDisplayName.localizedCaseInsensitiveCompare($1.sectionedDisplayName)
                    == .orderedAscending
            }
        }
    }

    var body: some View {
        PaneScaffold {
            PaneHeader(subtitle: "Choose the model that turns your speech into text.")

            SwitchedFromCloudBanner(registry: registry, credit: credit)

            InUseGroup(registry: registry, onShowCloudSettings: onShowCloudSettings)

            ForEach(visibleGroups) { group in
                ModelGroupSection(
                    group: group,
                    models: models(in: group),
                    registry: registry,
                    explainsAccuracy: group == visibleGroups.first,
                    onShowCloudSettings: onShowCloudSettings
                )
                #if arch(x86_64)
                if group == .local {
                    IntelGPUCard()
                }
                #endif
            }
        }
        .animation(motion.select, value: registry.activeModelId)
        .animation(motion.layout, value: credit.switchedFromModelId)
        .animation(motion.layout, value: scope)
        .animation(motion.layout, value: sort)
        .toolbar { toolbarContent }
        .onAppear { registry.refreshInstalledState() }
    }

    // MARK: - Toolbar

    /// Two native pop-ups, like History's filter, so they stay in reach while
    /// the list scrolls.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Show", selection: $scope) {
                ForEach(ModelScope.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Show all models, only models on this Mac, or only cloud models")
        }

        ToolbarItem(placement: .primaryAction) {
            Picker("Sort", selection: $sort) {
                ForEach(ModelSort.allCases) { option in
                    Text("Sort by \(option.title)").tag(option)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Sort the models in each group")
        }
    }
}

// MARK: - Groups

/// The provider groups. One value owns the title and the privacy sentence, so
/// every place that lists models by provider agrees on both.
enum ModelGroup: String, Identifiable {
    case local, openAI, elevenLabs, groq

    var id: String { rawValue }

    var provider: CloudProvider? {
        switch self {
        case .local: return nil
        case .openAI: return .openAI
        case .elevenLabs: return .elevenLabs
        case .groq: return .groq
        }
    }

    var title: String {
        switch self {
        case .local: return "On this Mac"
        case .openAI: return "OpenAI"
        case .elevenLabs: return "ElevenLabs"
        case .groq: return "Groq"
        }
    }

    /// Where the audio goes and who bills it.
    var subtitle: String {
        switch self {
        case .local:
            return "Audio never leaves this Mac. Free to run."
        case .openAI:
            return "Audio is sent to OpenAI and billed to your API key."
        case .elevenLabs:
            return "Audio is sent to ElevenLabs and billed to your API key."
        case .groq:
            return "Audio is sent to Groq and billed to your API key."
        }
    }

    /// A model belongs to the group whose provider it names, and to `.local`
    /// when it names none.
    func contains(_ model: ModelDescriptor) -> Bool {
        model.backend.cloudProvider == provider
    }

    /// `models` split by group in reading order, keeping catalog order within a
    /// group and dropping empty ones.
    static func sections(of models: [ModelDescriptor]) -> [(group: ModelGroup, models: [ModelDescriptor])] {
        [ModelGroup.local, .openAI, .elevenLabs, .groq].compactMap { group in
            let members = models.filter(group.contains)
            return members.isEmpty ? nil : (group, members)
        }
    }

    static func group(for model: ModelDescriptor) -> ModelGroup {
        guard let provider = model.backend.cloudProvider else { return .local }
        switch provider {
        case .openAI: return .openAI
        case .elevenLabs: return .elevenLabs
        case .groq: return .groq
        }
    }
}

/// One provider as a small table: header (title + key or disk status), a
/// column-title row, the models, and the privacy sentence as the footer.
private struct ModelGroupSection: View {
    let group: ModelGroup
    let models: [ModelDescriptor]
    @Bindable var registry: ModelRegistry
    /// The first group on screen carries the one-line accuracy legend.
    let explainsAccuracy: Bool
    let onShowCloudSettings: () -> Void
    @State private var isShowingKeyEntry = false
    @State private var width: CGFloat = 640

    /// Below this the languages column is dropped so names keep room.
    private var isCompact: Bool { width < 560 }

    private var footer: String {
        explainsAccuracy ? "\(group.subtitle) \(ModelFacts.accuracyScale)" : group.subtitle
    }

    var body: some View {
        SettingsGroup(group.title, footer: footer) {
            StatColumnTitles(costTitle: group.provider == nil ? "Size" : "Price", isCompact: isCompact)
            ForEach(models) { model in
                ModelRow(
                    model: model,
                    registry: registry,
                    isCompact: isCompact,
                    onAddKey: { isShowingKeyEntry = true }
                )
            }
        } accessory: {
            accessory
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @ViewBuilder
    private var accessory: some View {
        if let provider = group.provider {
            if provider.hasAPIKey {
                if CloudCreditStatus.shared.isOutOfCredit(provider) {
                    StatusLabel(level: .warning, text: keyStatusText(provider, FailureCardCopy.outOfCreditLabel))
                } else {
                    StatusLabel(level: .ready, text: keyStatusText(provider, "Connected"))
                }
            } else {
                HStack(spacing: Space.s4) {
                    if let reason = ProviderKeyNeed.current(for: provider, registry: registry).statusText {
                        StatusLabel(level: .warning, text: reason)
                    }
                    AddAPIKeyButton(
                        provider: provider,
                        isPresented: $isShowingKeyEntry,
                        onShowCloudSettings: onShowCloudSettings
                    )
                }
            }
        } else if registry.totalDiskUsageBytes > 0 {
            Text("\(registry.totalDiskUsageBytes.formattedDiskSize) on disk")
                .typo(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.inkMuted)
                .fixedSize()
        }
    }

    /// "Connected · …abcd": the suffix says which key.
    private func keyStatusText(_ provider: CloudProvider, _ status: String) -> String {
        guard let suffix = provider.apiKeySuffix else { return status }
        return "\(status) · …\(suffix)"
    }
}

// MARK: - Columns

/// The fixed column widths every row and title row share, so values line up
/// down a group. Numbers align on their trailing edge.
private enum StatColumn {
    static let accuracy: CGFloat = 56
    static let speed: CGFloat = 64
    static let cost: CGFloat = 64
    static let languages: CGFloat = 60
    /// "✓ Installed" or the Download button, just before ⋯.
    static let status: CGFloat = 84
    static let spacing: CGFloat = Space.s5
    /// Trailing padding that puts the ⋯ glyph, not its 28pt hit area, on the
    /// group's trailing edge.
    static let trailingPadding = FormMetrics.rowHorizontalPadding - (FormMetrics.iconButton - 14) / 2
}

/// The stat cells, laid out on the shared column widths. Compact (a narrow
/// window) keeps accuracy and size or price.
private struct StatCells: View {
    let accuracy: String
    let speed: String
    let cost: String
    let languages: String
    var languagesHelp: String?
    let isCompact: Bool
    var style: Typo.Style = .body
    var color: Color = Palette.inkMuted

    var body: some View {
        HStack(spacing: StatColumn.spacing) {
            cell(accuracy, width: StatColumn.accuracy, alignment: .trailing)
            if !isCompact {
                cell(speed, width: StatColumn.speed, alignment: .leading)
            }
            cell(cost, width: StatColumn.cost, alignment: .trailing)
            if !isCompact {
                cell(languages, width: StatColumn.languages, alignment: .trailing)
                    .help(languagesHelp ?? "")
            }
        }
    }

    private func cell(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .typo(style)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }
}

/// The column titles under a group header, as the plate's first row.
private struct StatColumnTitles: View {
    let costTitle: String
    let isCompact: Bool

    var body: some View {
        HStack(spacing: Space.s5) {
            Text("Model")
                .frame(maxWidth: .infinity, alignment: .leading)
            StatCells(
                accuracy: "Accuracy",
                speed: "Speed",
                cost: costTitle,
                languages: "Languages",
                isCompact: isCompact,
                style: .caption,
                color: Palette.inkMuted
            )
            .help(ModelFacts.accuracyScale)
            Color.clear.frame(width: StatColumn.status, height: 1)
            Color.clear.frame(width: FormMetrics.iconButton, height: 1)
        }
        .typo(.caption)
        .foregroundStyle(Palette.inkMuted)
        .padding(.leading, FormMetrics.rowHorizontalPadding)
        .padding(.trailing, StatColumn.trailingPadding)
        .padding(.vertical, Space.s3)
        .accessibilityHidden(true)
    }
}

// MARK: - Availability

/// Whether a model can run right now, and if not, what it needs. The rows, the
/// In Use pickers and the details footer all read this.
private enum ModelAvailability: Equatable {
    case ready
    case needsKey(CloudProvider)
    case outOfCredit
    case notDownloaded
    case downloading(Double)
    /// Installed, and being loaded into memory or compiled: usable, not a download.
    case loading
    case failed

    static func of(_ model: ModelDescriptor, registry: ModelRegistry) -> ModelAvailability {
        if let provider = model.backend.cloudProvider {
            // A cloud model's readiness is its key (and the provider's
            // balance); the registry marks it `.preparing` before every take.
            guard provider.hasAPIKey else { return .needsKey(provider) }
            return CloudCreditStatus.shared.isOutOfCredit(provider) ? .outOfCredit : .ready
        }
        // A preparation that began as a download stays one — progress and
        // Cancel — through its first compile, even once its files are on disk.
        if case .preparing(let fraction, _) = registry.readiness(for: model.id),
           registry.canCancelDownload(id: model.id) {
            return .downloading(fraction)
        }
        if ModelSwitchPolicy.isLoading(model, registry: registry) { return .loading }
        switch registry.readiness(for: model.id) {
        case .installed: return .ready
        case .notInstalled:
            return registry.downloadedLocalModelIDs.contains(model.id) ? .ready : .notDownloaded
        case .preparing(let fraction, _): return .downloading(fraction)
        case .failed: return .failed
        }
    }

    /// The problem, in the words a caption uses; nil when ready.
    var problem: String? {
        switch self {
        case .ready, .loading: return nil
        case .needsKey(let provider): return "No \(provider.displayName) API key"
        case .outOfCredit: return FailureCardCopy.outOfCreditLabel
        case .notDownloaded: return "Not downloaded"
        case .downloading(let fraction): return "Downloading… \(Int(fraction * 100))%"
        case .failed: return "Download failed"
        }
    }
}

/// The roles a model fills right now, in the order the In Use group lists them.
private enum ModelRole: String, CaseIterable, Identifiable {
    case dictation = "Dictation"
    case conversations = "Conversations"
    case secondShortcut = "Second shortcut"
    var id: String { rawValue }

    static func roles(of model: ModelDescriptor, registry: ModelRegistry) -> [ModelRole] {
        var roles: [ModelRole] = []
        if registry.activeModelId == model.id { roles.append(.dictation) }
        if registry.conversationModel?.id == model.id { roles.append(.conversations) }
        let hotkeys = HotkeyStore.shared
        if hotkeys.secondBinding != nil, hotkeys.secondModelId == model.id { roles.append(.secondShortcut) }
        return roles
    }
}

// MARK: - Switched-from banner

/// "Switched from GPT Transcribe when OpenAI ran out of credit." [Switch Back]
///
/// Shown only while a failure card's "Use for Dictation" switch still stands:
/// every pick in this pane goes through `ModelRegistry.setActive`, which
/// forgets it, and the active model must still be a local one.
private struct SwitchedFromCloudBanner: View {
    @Bindable var registry: ModelRegistry
    @Bindable var credit: CloudCreditStatus

    var body: some View {
        if let cloudModel {
            StatusPlate([
                StatusItem(
                    id: "switchedFromCloud",
                    level: .warning,
                    title: FailureCardCopy.switchedBanner(
                        cloudModelName: cloudModel.model.sectionedDisplayName,
                        provider: cloudModel.provider.displayName
                    ),
                    actionTitle: FailureCardCopy.switchBackTitle,
                    action: { registry.setActive(cloudModel.model.id) }
                ),
            ])
        }
    }

    private var cloudModel: (model: ModelDescriptor, provider: CloudProvider)? {
        guard let cloudId = credit.switchedFromModelId,
              let model = ModelCatalog.model(for: cloudId),
              let provider = model.backend.cloudProvider,
              let active = registry.activeModel,
              !active.isCloud
        else { return nil }
        return (model, provider)
    }
}

// MARK: - In Use

/// Where models get assigned: one picker per way of transcribing, the same
/// dropdown General and Conversations use. Each lists the models that can run
/// now, grouped by source; the caption says where the audio goes, or what's
/// missing.
private struct InUseGroup: View {
    @Bindable var registry: ModelRegistry
    let onShowCloudSettings: () -> Void
    @Bindable private var hotkeys = HotkeyStore.shared

    var body: some View {
        SettingsGroup("In Use") {
            if let model = registry.activeModel {
                InUseRow(title: "Dictation", model: model, registry: registry, onShowCloudSettings: onShowCloudSettings) {
                    MinimalDropdown(
                        selection: Binding(
                            get: { registry.activeModelId },
                            set: { registry.setActive($0) }
                        ),
                        sections: DropdownSection<String>.models(models(including: model.id), value: { $0.id }),
                        title: "Dictation model",
                        tooltip: ModelSwitchPolicy.canChangeDictationModel
                            ? "Choose the dictation model" : "Finish the current dictation first"
                    )
                    .disabled(!ModelSwitchPolicy.canChangeDictationModel)
                }
            }

            if let model = registry.conversationModel {
                InUseRow(
                    title: "Conversations",
                    lead: followsDictation ? followCaption(for: model) : nil,
                    model: model,
                    registry: registry,
                    onShowCloudSettings: onShowCloudSettings
                ) {
                    MinimalDropdown(
                        selection: Binding(
                            get: { followsDictation ? nil : registry.conversationModelId },
                            set: { registry.setConversationModel($0) }
                        ),
                        sections: conversationSections(current: model),
                        title: "Conversation model",
                        tooltip: conversationIsBusy
                            ? "Finish the current conversation first" : "Choose the conversation model"
                    )
                    // A conversation in flight reads this model when its
                    // transcription starts, so it holds still until it's done.
                    .disabled(conversationIsBusy)
                }
            }

            if let binding = hotkeys.secondBinding {
                // A stored id that is unset or gone from the catalog shows
                // "Choose a model" (as the Shortcut pane does), never a
                // default the shortcut wouldn't actually use.
                let model = hotkeys.secondModelId.flatMap { ModelCatalog.model(for: $0) }
                InUseRow(
                    title: "Second shortcut",
                    keys: binding.displayKeys,
                    model: model,
                    registry: registry,
                    onShowCloudSettings: onShowCloudSettings
                ) {
                    MinimalDropdown(
                        selection: Binding(
                            get: { model?.id },
                            set: { hotkeys.updateSecondModel(to: $0) }
                        ),
                        sections: DropdownSection<String?>.models(models(including: model?.id), value: { Optional($0.id) }),
                        placeholder: "Choose a model",
                        title: "Second shortcut model",
                        tooltip: "Choose the second shortcut's model"
                    )
                }
            }
        }
    }

    private var followsDictation: Bool {
        registry.conversationModelId.flatMap { ModelCatalog.model(for: $0) } == nil
    }

    private var conversationIsBusy: Bool { MeetingController.shared.isBusy }

    /// Models that can run now, plus `currentId` so the selection always has
    /// an item.
    private func models(including currentId: String?, excludingLive: Bool = false) -> [ModelDescriptor] {
        ModelCatalog.all.filter {
            ($0.id == currentId || ModelSwitchPolicy.isUsable($0, registry: registry))
                && !(excludingLive && $0.isRealtime)
        }
    }

    /// "Same as dictation" first (naming the model it resolves to), then the
    /// models that can transcribe a recording — live ones can't.
    private func conversationSections(current: ModelDescriptor) -> [DropdownSection<String?>] {
        let follow = DropdownSection<String?>(items: [
            DropdownItem(
                value: nil,
                title: "Same as dictation",
                detail: followsDictation ? current.nameWithSource : registry.dictationModelForConversations?.model.nameWithSource
            ),
        ])
        let explicit = followsDictation ? nil : registry.conversationModelId
        return [follow] + DropdownSection<String?>.models(models(including: explicit, excludingLive: true), value: { Optional($0.id) })
    }

    private func followCaption(for model: ModelDescriptor) -> String {
        model.id == registry.activeModelId ? "Same as dictation." : "Stands in for the live dictation model."
    }
}

/// "Dictation" over "Audio is sent to OpenAI.", with the picker (and a fix
/// button when the model can't run) on the right.
private struct InUseRow<Control: View>: View {
    let title: String
    var keys: [String]?
    var lead: String?
    /// Nil when the role has no model yet (the picker says "Choose a model").
    let model: ModelDescriptor?
    let registry: ModelRegistry
    let onShowCloudSettings: () -> Void
    @ViewBuilder var picker: Control
    @State private var isShowingKeyEntry = false

    init(
        title: String,
        keys: [String]? = nil,
        lead: String? = nil,
        model: ModelDescriptor?,
        registry: ModelRegistry,
        onShowCloudSettings: @escaping () -> Void,
        @ViewBuilder picker: () -> Control
    ) {
        self.title = title
        self.keys = keys
        self.lead = lead
        self.model = model
        self.registry = registry
        self.onShowCloudSettings = onShowCloudSettings
        self.picker = picker()
    }

    private var availability: ModelAvailability {
        model.map { .of($0, registry: registry) } ?? .ready
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s4) {
                    Text(title)
                        .typo(.body)
                        .foregroundStyle(Palette.ink)
                    if let keys {
                        Keycap(keys: keys, size: .small)
                    }
                }
                caption
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            fix
            picker
        }
        .settingsRowPadding()
        .accessibilityElement(children: .contain)
    }

    /// Only what the picker doesn't already say: the problem, or that the
    /// model follows dictation.
    @ViewBuilder
    private var caption: some View {
        if let problem = availability.problem {
            StatusLabel(level: availability == .failed ? .error : .warning, text: problem)
        } else if let lead {
            Text(lead)
                .typo(.caption)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    @ViewBuilder
    private var fix: some View {
        switch availability {
        case .needsKey(let provider):
            AddAPIKeyButton(
                provider: provider,
                isPresented: $isShowingKeyEntry,
                purpose: title.lowercased(),
                onShowCloudSettings: onShowCloudSettings
            )
        case .notDownloaded, .failed:
            if let model {
                let verb = availability == .failed ? "Retry" : "Download"
                Button(verb) {
                    Task { await registry.prepareModel(id: model.id) }
                }
                .buttonTier(.secondary)
                .controlSize(.small)
                .help("\(verb) \(model.sectionedDisplayName) (\(ModelFacts.approximateSize(model)))")
                .accessibilityLabel("\(verb == "Retry" ? "Retry the download of" : "Download") the \(title.lowercased()) model")
            }
        case .ready, .outOfCredit, .downloading, .loading:
            EmptyView()
        }
    }
}

// MARK: - Row

/// One catalog row: name (with a lock when its provider has no key, and the
/// Recommended badge), the stat columns, and ⋯. A second line appears only
/// when there is something to say: the roles it fills, or its download.
/// Clicking the row opens its details; it never downloads.
private struct ModelRow: View {
    let model: ModelDescriptor
    @Bindable var registry: ModelRegistry
    let isCompact: Bool
    let onAddKey: () -> Void
    @State private var isHovering = false
    @State private var isShowingDetails = false
    @State private var isConfirmingDelete = false
    @State private var afterDetailsClose: AfterDetailsClose?
    @Environment(\.motion) private var motion
    @Environment(\.increaseContrast) private var increaseContrast

    private enum AfterDetailsClose { case delete, addKey }

    private var availability: ModelAvailability { .of(model, registry: registry) }
    private var readiness: ModelReadiness { registry.readiness(for: model.id) }
    private var roles: [ModelRole] { ModelRole.roles(of: model, registry: registry) }
    private var name: String { model.sectionedDisplayName }
    private var isActive: Bool { registry.activeModelId == model.id }
    private var isConversationModel: Bool { registry.conversationModel?.id == model.id }
    private var canUseForConversations: Bool {
        !model.isRealtime && ModelSwitchPolicy.isUsable(model, registry: registry) && !isConversationModel
            && !MeetingController.shared.isBusy
    }
    private var needsKey: Bool {
        if case .needsKey = availability { return true }
        return false
    }
    /// The roles it fills, a missing key, or a download in progress or failed
    /// go on a second line; most rows are one line.
    private var hasSecondLine: Bool {
        if !roles.isEmpty || needsKey || isRecommended { return true }
        switch availability {
        case .downloading, .failed: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s5) {
                Button {
                    isShowingDetails = true
                } label: {
                    nameCell
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onKeyPress(.return) {
                    isShowingDetails = true
                    return .handled
                }
                .help("Show details")
                .accessibilityLabel(name)
                .accessibilityValue(accessibilityValue)
                .accessibilityHint("Shows details and options")
                .accessibilityAddTraits(roles.isEmpty ? [] : [.isSelected])

                StatCells(
                    accuracy: ModelFacts.accuracyValue(model),
                    speed: ModelFacts.speed(model),
                    cost: ModelFacts.costValue(model, readiness: readiness),
                    languages: ModelFacts.languagesValue(model),
                    languagesHelp: ModelBadges.languagesLabel(model.languages),
                    isCompact: isCompact
                )
                .accessibilityHidden(true)

                // The slot keeps its width on every row (cloud rows leave it
                // empty) so the stat columns stay under their titles.
                ZStack(alignment: .trailing) {
                    Color.clear.frame(width: StatColumn.status, height: 1)
                    statusCell
                }

                moreMenu
            }

            if hasSecondLine {
                secondLine
                    .padding(.trailing, FormMetrics.iconButton + Space.s5)
            }
        }
        .padding(.leading, FormMetrics.rowHorizontalPadding)
        .padding(.trailing, StatColumn.trailingPadding)
        .padding(.vertical, Space.s3 + 1)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(isHovering ? Palette.plateHover(increaseContrast: increaseContrast) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { isShowingDetails = true }
        .onHover { isHovering = $0 }
        .animation(motion.hover, value: isHovering)
        .contextMenu { menuItems }
        .confirmationDialog(
            "Delete \(name)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { registry.deleteModel(id: model.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Frees \(ModelFacts.size(model, readiness: readiness) ?? "space") on disk. "
                + "You can download it again anytime.")
        }
    }

    /// Regular weight; semibold only for a model in use, so those stand out.
    private var nameCell: some View {
        Text(name)
            .typo(roles.isEmpty ? .body : .headline)
            .foregroundStyle(needsKey ? Palette.inkMuted : Palette.ink)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var isRecommended: Bool { model.id == ModelBadges.recommendedId }

    /// Local models say whether they're on this Mac: "✓ Installed", or the
    /// Download button. Cloud rows leave it empty; their header has the key.
    @ViewBuilder
    private var statusCell: some View {
        if !model.isCloud {
            switch availability {
            case .ready, .loading:
                StatusTag("Installed")
            case .notDownloaded:
                Button("Download") {
                    Task { await registry.prepareModel(id: model.id) }
                }
                .buttonTier(.secondary)
                .controlSize(.small)
                .help("Download \(name) (\(ModelFacts.approximateSize(model)))")
                .accessibilityLabel("Download \(name), \(ModelFacts.approximateSize(model))")
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var secondLine: some View {
        HStack(spacing: Space.s5) {
            if isRecommended {
                BadgeLabel("Recommended")
            }
            if !roles.isEmpty {
                StatusTag("In use for " + ListFormatter.localizedString(byJoining: roles.map { $0.rawValue.lowercased() }))
            }
            if needsKey, let provider = model.backend.cloudProvider {
                StatusTag("Add \(provider.apiKeyPhrase) to use", systemImage: "lock.fill")
            }
            switch availability {
            case .downloading, .failed:
                LocalDownloadControl(model: model, registry: registry)
            default:
                EmptyView()
            }
        }
    }

    // MARK: Menu and details

    private var moreMenu: some View {
        IconMenu(label: "Details and options for \(name)") {
            menuItems
        }
        .popover(isPresented: $isShowingDetails, arrowEdge: .leading) {
            detailsPopover
        }
    }

    private var detailsPopover: some View {
        ModelDetailsPopover(
            model: model,
            registry: registry,
            onUseForDictation: {
                isShowingDetails = false
                registry.setActive(model.id)
            },
            onUseForConversations: {
                isShowingDetails = false
                registry.setConversationModel(model.id)
            },
            onDownload: {
                Task { await registry.prepareModel(id: model.id) }
            },
            onDelete: readiness.isInstalled && !model.isCloud ? {
                afterDetailsClose = .delete
                isShowingDetails = false
            } : nil,
            onAddKey: {
                afterDetailsClose = .addKey
                isShowingDetails = false
            }
        )
        // The follow-up presents only once the popover is gone, so the
        // confirmation dialog and the key popover never race its close.
        .onDisappear {
            switch afterDetailsClose {
            case .delete: isConfirmingDelete = true
            case .addKey: onAddKey()
            case nil: break
            }
            afterDetailsClose = nil
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Use for Dictation") { registry.setActive(model.id) }
            .disabled(isActive || !ModelSwitchPolicy.isUsable(model, registry: registry) || !ModelSwitchPolicy.canChangeDictationModel)
        if !model.isRealtime {
            Button("Use for Conversations") { registry.setConversationModel(model.id) }
                .disabled(!canUseForConversations)
        }
        Divider()
        Button("Details…") { isShowingDetails = true }
        if needsKey {
            Button("Add API Key…", action: onAddKey)
        }

        if !model.isCloud {
            switch readiness {
            case .notInstalled, .failed:
                Button("Download (\(ModelFacts.approximateSize(model)))") {
                    Task { await registry.prepareModel(id: model.id) }
                }
            case .installed:
                Divider()
                Button("Delete Model…", role: .destructive) { isConfirmingDelete = true }
            case .preparing:
                if registry.canCancelDownload(id: model.id) {
                    Button("Cancel Download") { registry.cancelDownload(id: model.id) }
                }
            }
        }
    }

    // MARK: Accessibility

    /// The stats a sighted reader scans in the columns, the roles and the state.
    private var accessibilityValue: String {
        var parts = [ModelFacts.spokenStats(model, readiness: readiness)]
        if !roles.isEmpty {
            parts.append("Used for " + ListFormatter.localizedString(byJoining: roles.map(\.rawValue)))
        }
        if let problem = availability.problem {
            parts.append(problem)
        } else if !model.isCloud {
            parts.append("Installed")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Local download

/// A local model's download on the row's second line: the progress with
/// Cancel, or the failure with Retry.
private struct LocalDownloadControl: View {
    let model: ModelDescriptor
    @Bindable var registry: ModelRegistry

    var body: some View {
        switch registry.readiness(for: model.id) {
        case .preparing(let fraction, let message):
            HStack(spacing: Space.s3) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 160)
                Text("\(message) \(Int(fraction * 100))%")
                    .typo(.caption)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
                if registry.canCancelDownload(id: model.id) {
                    IconButton("xmark.circle.fill", label: "Cancel download of \(model.sectionedDisplayName)") {
                        registry.cancelDownload(id: model.id)
                    }
                }
            }
            .accessibilityElement(children: .contain)

        case .failed(let message):
            HStack(spacing: Space.s4) {
                Text(registry.failureSentence(for: model.id) ?? "Download failed")
                    .typo(.caption)
                    .foregroundStyle(Palette.signalWarn)
                    .lineLimit(1)
                    .help(message)
                Button("Retry") {
                    Task { await registry.prepareModel(id: model.id) }
                }
                .buttonTier(.secondary)
                .controlSize(.small)
                .accessibilityLabel("Retry download of \(model.sectionedDisplayName)")
            }

        case .installed, .notInstalled:
            EmptyView()
        }
    }
}

/// "Add API Key…" and the key field it opens, in place. The presentation flag
/// is the caller's, so a row's menu can open the same popover.
private struct AddAPIKeyButton: View {
    let provider: CloudProvider
    @Binding var isPresented: Bool
    /// What the key is for ("dictation"), so several of these read apart.
    var purpose: String?
    let onShowCloudSettings: () -> Void

    var body: some View {
        Button("Add API Key…") {
            isPresented = true
        }
        .buttonTier(.secondary)
        .controlSize(.small)
        .help("Add your \(provider.displayName) API key without leaving this list")
        .accessibilityLabel(purpose.map { "Add \(provider.displayName) API key for \($0)" } ?? "Add \(provider.displayName) API key")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text("\(provider.displayName) API Key")
                    .typo(.title)
                    .foregroundStyle(Palette.ink)

                APIKeyEntryView(config: .forProvider(provider), onConnected: {
                    isPresented = false
                })

                Button("All cloud settings…") {
                    isPresented = false
                    onShowCloudSettings()
                }
                .buttonStyle(TextLinkButtonStyle(font: Typo.caption))
            }
            .padding(Space.s6)
            .frame(width: 380)
        }
    }
}

// MARK: - Details popover

/// The facts behind a row, in plain words, with the raw benchmark figures
/// behind a disclosure. The footer shows the roles the model already fills
/// and offers the others; installed local models can be deleted from the
/// Size row.
private struct ModelDetailsPopover: View {
    let model: ModelDescriptor
    @Bindable var registry: ModelRegistry
    let onUseForDictation: () -> Void
    let onUseForConversations: () -> Void
    let onDownload: () -> Void
    let onDelete: (() -> Void)?
    let onAddKey: () -> Void
    @State private var showsSources = false

    private static let labelWidth: CGFloat = 92

    private var availability: ModelAvailability { .of(model, registry: registry) }
    private var isActive: Bool { registry.activeModelId == model.id }
    private var isConversationModel: Bool { registry.conversationModel?.id == model.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text(model.sectionedDisplayName)
                        .typo(.title)
                        .foregroundStyle(Palette.ink)
                    if model.id == ModelBadges.recommendedId {
                        BadgeLabel("Recommended")
                    }
                }
                Text(model.notes)
                    .typo(.body)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                useStatus
                    .padding(.top, Space.s1)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s6, verticalSpacing: Space.s4 + 2) {
                ForEach(ModelFacts.facts(for: model, registry: registry)) { fact in
                    GridRow {
                        Text(fact.label)
                            .typo(.body)
                            .foregroundStyle(Palette.inkMuted)
                            .frame(width: Self.labelWidth, alignment: .leading)
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text(fact.value)
                                .typo(.body)
                                .foregroundStyle(Palette.ink)
                            if let detail = fact.detail {
                                Text(detail)
                                    .typo(.caption)
                                    .foregroundStyle(Palette.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            sources

            Divider()

            // One row: Delete on the leading edge, as in the Edit Action
            // sheet; the actions on the trailing edge.
            HStack(spacing: Space.s4) {
                deleteButton
                Spacer(minLength: Space.s4)
                actions
            }
            .lineLimit(1)
        }
        .padding(Space.s6)
        .frame(width: 440, alignment: .leading)
        .presentationBackground(Palette.plate)
    }

    // MARK: Sources

    /// A quiet disclosure: chevron and label as one hit target, in secondary
    /// ink, so it reads as a footnote rather than as data.
    @ViewBuilder
    private var sources: some View {
        let lines = ModelFacts.sourceLines(for: model)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Space.s3) {
                Button {
                    showsSources.toggle()
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(showsSources ? 90 : 0))
                        Text(model.isQualityApproximate ? "Estimated from public benchmarks" : "Benchmark sources")
                            .typo(.caption)
                    }
                    .foregroundStyle(Palette.inkMuted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsSources ? "Expanded" : "Collapsed")

                if showsSources {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .typo(.caption)
                                .foregroundStyle(Palette.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.leading, Space.s4)
                }
            }
        }
    }

    // MARK: Status and footer

    /// "✓ In use for dictation and conversations", or "Not in use".
    @ViewBuilder
    private var useStatus: some View {
        let roles = ModelRole.roles(of: model, registry: registry)
        if roles.isEmpty {
            Text("Not in use")
                .typo(.caption)
                .foregroundStyle(Palette.inkMuted)
        } else {
            StatusTag("In use for " + ListFormatter.localizedString(byJoining: roles.map { $0.rawValue.lowercased() }))
        }
    }

    /// The destructive tier: bordered, red label.
    @ViewBuilder
    private var deleteButton: some View {
        if let onDelete {
            Button("Delete Model…", role: .destructive, action: onDelete)
                .buttonTier(.destructive)
                .fixedSize()
                .help("Delete this model from your Mac (\(ModelFacts.size(model, readiness: registry.readiness(for: model.id)) ?? ""))")
        }
    }

    /// The roles the model doesn't fill yet, as buttons; a model that can't
    /// run yet offers its fix instead.
    @ViewBuilder
    private var actions: some View {
        switch availability {
        case .needsKey:
            Button("Add API Key…", action: onAddKey)
                .buttonTier(.primary)
        case .notDownloaded:
            Button("Download (\(ModelFacts.approximateSize(model)))", action: onDownload)
                .buttonTier(.primary)
        case .failed:
            Button("Retry Download", action: onDownload)
                .buttonTier(.primary)
        case .downloading(let fraction):
            Text("Downloading… \(Int(fraction * 100))%")
                .typo(.body)
                .monospacedDigit()
                .foregroundStyle(Palette.inkMuted)
        case .ready, .outOfCredit, .loading:
            // "Use for [Conversations] [Dictation]": only the roles it doesn't
            // fill yet; the status line under the title names the ones it does.
            let offersConversations = !model.isRealtime && !isConversationModel
            if offersConversations || !isActive {
                Text("Use for")
                    .typo(.body)
                    .foregroundStyle(Palette.inkMuted)
                if offersConversations {
                    let busy = MeetingController.shared.isBusy
                    Button("Conversations", action: onUseForConversations)
                        .buttonTier(isActive ? .primary : .secondary)
                        .disabled(busy)
                        .help(busy ? "Finish the current conversation first" : "Transcribe conversations with this model")
                        .accessibilityLabel("Use for conversations")
                }
                if !isActive {
                    let canChange = ModelSwitchPolicy.canChangeDictationModel
                    Button("Dictation", action: onUseForDictation)
                        .buttonTier(.primary)
                        .disabled(!canChange)
                        .help(canChange ? "Dictate with this model" : "Finish the current dictation first")
                        .accessibilityLabel("Use for dictation")
                }
            }
        }
    }
}

// MARK: - Facts

/// Every string the pane derives from a `ModelDescriptor`, in one place, so the
/// rows, the In Use group and the details popover can't disagree.
private enum ModelFacts {

    /// The accuracy column: "8.9", or "—" for an unmeasured model.
    static func accuracyValue(_ model: ModelDescriptor) -> String {
        guard let quality = model.quality else { return "—" }
        return String(format: "%.1f", quality)
    }

    /// The catalog's relative speed (1–10) in words.
    static func speed(_ model: ModelDescriptor) -> String {
        switch model.speed {
        case 9...: return "Very fast"
        case 7...8: return "Fast"
        case 5...6: return "Medium"
        default: return "Slow"
        }
    }

    /// The size column for local models (real size once installed), the price
    /// column for cloud ones; "—" when the catalog has no price.
    static func costValue(_ model: ModelDescriptor, readiness: ModelReadiness) -> String {
        if model.isCloud { return price(model) ?? "—" }
        return size(model, readiness: readiness) ?? "—"
    }

    /// The count alone ("99", "99+", "25"); the full wording ("25 European
    /// languages") is the cell's tooltip and the details row.
    static func languagesValue(_ model: ModelDescriptor) -> String {
        model.languages.split(separator: " ").first.map(String.init) ?? model.languages
    }

    /// Nil when the catalog has no price; local models price at 0.
    static func price(_ model: ModelDescriptor) -> String? {
        guard let price = model.pricePerHourUSD, price > 0 else { return nil }
        return String(format: "$%.2f/hr", price)
    }

    /// The real on-disk size once installed, the catalog's estimate before.
    static func size(_ model: ModelDescriptor, readiness: ModelReadiness) -> String? {
        guard !model.isCloud else { return nil }
        if case .installed(let bytes) = readiness { return bytes.formattedDiskSize }
        return approximateSize(model)
    }

    static func approximateSize(_ model: ModelDescriptor) -> String {
        model.approxSizeBytes.formattedDiskSize
    }

    /// The columns as VoiceOver reads them: "Accuracy 8.9 out of 10, Fast,
    /// 1.62 GB, 99 languages".
    static func spokenStats(_ model: ModelDescriptor, readiness: ModelReadiness) -> String {
        let accuracy = model.quality.map { String(format: "Accuracy %.1f out of 10", $0) } ?? "Accuracy not measured"
        return [accuracy, speed(model), costValue(model, readiness: readiness), ModelBadges.languagesLabel(model.languages)]
            .joined(separator: ", ")
    }

    // MARK: Details popover

    struct Fact: Identifiable {
        let label: String
        let value: String
        var detail: String?
        var id: String { label }
    }

    static func facts(for model: ModelDescriptor, registry: ModelRegistry) -> [Fact] {
        let readiness = registry.readiness(for: model.id)
        var facts: [Fact] = []

        if let quality = model.quality {
            facts.append(Fact(
                label: "Accuracy",
                value: String(format: "%.1f/10", quality),
                detail: accuracyComparison(model, quality: quality)
            ))
        } else {
            facts.append(Fact(label: "Accuracy", value: "Not measured yet"))
        }

        facts.append(Fact(label: "Speed", value: speed(model)))
        facts.append(Fact(label: "Text appears", value: model.isRealtime ? "While you speak (live)" : "When you stop"))

        if !model.isCloud {
            if case .installed(let bytes) = readiness {
                facts.append(Fact(label: "Size", value: "\(bytes.formattedDiskSize) on disk"))
            } else {
                facts.append(Fact(label: "Size", value: "\(approximateSize(model)) download"))
            }
        }

        facts.append(Fact(label: "Languages", value: ModelBadges.languagesLabel(model.languages)))

        if let provider = model.backend.cloudProvider?.displayName {
            let cost = model.pricePerHourUSD.flatMap { $0 > 0 ? String(format: "$%.2f per hour of audio", $0) : nil }
            facts.append(Fact(label: "Cost", value: cost ?? "Not published", detail: "Billed to your \(provider) API key"))
            facts.append(Fact(label: "Runs on", value: "\(provider)'s servers"))
        } else {
            facts.append(Fact(label: "Cost", value: "Free"))
            facts.append(Fact(label: "Runs on", value: "This Mac", detail: "Your audio never leaves it"))
        }

        return facts
    }

    /// The score as a plain comparison with Whisper Large v3. Three points is
    /// one doubling of word errors (`ModelQualityScore`), so the ratio follows
    /// from the score itself.
    static func accuracyComparison(_ model: ModelDescriptor, quality: Double) -> String {
        if model.id == "whisper-large-v3" {
            return "The reference the scores are measured against"
        }
        let ratio = pow(2, (ModelQualityScore.referenceScore - quality) / ModelQualityScore.pointsPerDoubling)
        if abs(ratio - 1) < 0.05 {
            return "About as accurate as Whisper Large v3"
        }
        if ratio < 1 {
            return "About \(roundedPercent(1 - ratio))% fewer errors than Whisper Large v3"
        }
        if ratio < 1.5 {
            return "About \(roundedPercent(ratio - 1))% more errors than Whisper Large v3"
        }
        return String(format: "About %.1f× the errors of Whisper Large v3", ratio)
    }

    /// To the nearest 5%, never below 5.
    private static func roundedPercent(_ fraction: Double) -> Int {
        max(5, Int((fraction * 20).rounded()) * 5)
    }

    /// The benchmark figures behind the score, with their caveats, the scale
    /// and where the price comes from.
    static func sourceLines(for model: ModelDescriptor) -> [String] {
        var lines: [String] = []
        for measurement in model.benchmarks {
            let percent = String(format: "%.1f", measurement.percent)
            let reference = String(format: "%.1f", measurement.benchmark.whisperLargeV3Percent)
            var line = "\(benchmarkName(measurement.benchmark)): \(percent)% of words wrong "
                + "(Whisper Large v3: \(reference)%)."
            if measurement.isEstimate { line += " Estimate." }
            if let note = measurement.note { line += " \(note)" }
            lines.append(line)
        }
        guard !lines.isEmpty else { return [] }
        lines.append("The score: Whisper Large v3 is 8, and 3 points lower means twice as many word errors.")
        if let provider = model.backend.cloudProvider?.displayName, model.pricePerHourUSD != nil {
            lines.append("Price: \(provider)'s list price per hour of audio, September 2026. Approximate.")
        }
        return lines
    }

    static let accuracyScale = "Accuracy is out of 10; higher means fewer word errors."

    private static func benchmarkName(_ benchmark: WERMeasurement.Benchmark) -> String {
        switch benchmark {
        case .openASRLeaderboard: return "Open ASR Leaderboard (English average)"
        case .artificialAnalysis: return "Artificial Analysis AA-WER"
        }
    }
}

// MARK: - Badges

/// Labels derived from the static catalog, kept in the Settings layer so
/// `ModelRegistry` stays free of UI concerns.
private enum ModelBadges {
    /// The one recommendation badge; "most accurate" is the accuracy column
    /// and the sort order now.
    static let recommendedId = ModelCatalog.defaultModelID

    /// `languages` is a free string ("99", "90+", "25 European languages");
    /// " languages" is appended only to a bare count.
    static func languagesLabel(_ languages: String) -> String {
        let numericish = languages.contains(where: \.isNumber)
            && languages.allSatisfy { $0.isNumber || $0 == "+" }
        return numericish ? "\(languages) languages" : languages
    }
}
