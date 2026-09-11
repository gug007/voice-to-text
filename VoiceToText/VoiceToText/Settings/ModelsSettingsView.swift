import SwiftUI

// MARK: - The Models pane
//
// A hero card answering "what am I dictating with, and does it work", then one
// flush plate per provider group: "On this Mac", "OpenAI", "ElevenLabs".
//
// The grouping is what makes the rows short. Where the audio goes, who bills
// it, whether the key is connected and how much disk the group occupies are all
// facts about a *group*, so they are stated once in its header row. A model row
// then carries only what distinguishes it from the row above it: its name, at
// most one editorial chip, and the three numbers a reader is actually choosing
// between (quality, price or size, languages).
//
// This replaced 14 identical floating cards that repeated "Cloud", "Connected"
// and "99+ languages" on every one of them, signalled the active model three
// ways at once (accent bar + tint wash + ACTIVE chip) while offering no "choose
// this" affordance, and selected a row with an `onTapGesture` no keyboard could
// reach. Selection is a real `Button` with a radio indicator now, and the
// indicator is the only thing that says "active".

struct ModelsPane: View {
    @Bindable var registry: ModelRegistry
    var onShowCloudSettings: () -> Void = {}
    @Environment(\.motion) private var motion
    @State private var scope: ModelScope = .all
    @State private var sort: ModelSort = .quality

    enum ModelScope: String, CaseIterable, Identifiable {
        case all, local, cloud
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .local: return "On this Mac"
            case .cloud: return "Cloud"
            }
        }

        var symbol: String? {
            switch self {
            case .all: return nil
            case .local: return "laptopcomputer"
            case .cloud: return "cloud.fill"
            }
        }

        /// The groups this scope shows, in reading order. Empty ones are dropped
        /// downstream, so a catalog without ElevenLabs models simply has no
        /// ElevenLabs plate rather than an empty one.
        var groups: [ModelGroup] {
            switch self {
            case .all: return [.local, .openAI, .elevenLabs]
            case .local: return [.local]
            case .cloud: return [.openAI, .elevenLabs]
            }
        }
    }

    enum ModelSort: String, CaseIterable, Identifiable {
        case featured, quality, speed, name
        var id: String { rawValue }

        var title: String {
            switch self {
            case .featured: return "Featured"
            case .quality: return "Quality"
            case .speed: return "Speed"
            case .name: return "Name"
            }
        }

        /// The sort menu uses `.labelStyle(.titleAndIcon)`, so every option
        /// needs a glyph — the icons are what survive a condensed menu bar.
        var symbol: String {
            switch self {
            case .featured: return "sparkles"
            case .quality: return "target"
            case .speed: return "bolt.fill"
            case .name: return "textformat"
            }
        }
    }

    /// Sort runs *within* a group, never across them — a "by quality" list that
    /// interleaved local and cloud models would undo the grouping that lets the
    /// rows be this short.
    private func models(in group: ModelGroup) -> [ModelDescriptor] {
        sorted(ModelCatalog.all.filter(group.contains))
    }

    private var visibleGroups: [ModelGroup] {
        scope.groups.filter { !models(in: $0).isEmpty }
    }

    /// Swift's `sorted(by:)` is stable, so ties keep their curated catalog order.
    private func sorted(_ models: [ModelDescriptor]) -> [ModelDescriptor] {
        switch sort {
        case .featured:
            return models
        case .quality:
            // `quality` is derived straight from published word error rates, so
            // it is the whole key — there is nothing left to break ties with
            // that isn't already in the number. Unscored models sort last, and
            // the stable sort leaves genuine ties in catalog order.
            return models.sorted {
                ($0.quality ?? -1) > ($1.quality ?? -1)
            }
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
            PaneHeader(
                title: "Models",
                subtitle: "Pick the model you want to use for dictation."
            )

            ActiveModelCard(registry: registry, onShowCloudSettings: onShowCloudSettings)

            ForEach(visibleGroups) { group in
                ModelGroupPlate(
                    group: group,
                    models: models(in: group),
                    registry: registry,
                    onShowCloudSettings: onShowCloudSettings
                )
            }
        }
        // Selection changes animate across the whole pane rather than per-row,
        // so the hero and the chosen row adopt the accent in one motion.
        .animation(motion.select, value: registry.activeModelId)
        // Filtering and reordering move rows, which is layout, not selection.
        .animation(motion.layout, value: scope)
        .animation(motion.layout, value: sort)
        .toolbar { toolbarContent }
        .onAppear { registry.refreshInstalledState() }
    }

    // MARK: - Toolbar
    //
    // The scope filter and the sort control were two homeless widgets floating
    // in the pane's first row — a hand-rolled capsule segmented control and a
    // "Sort by" label next to a custom dropdown. They are toolbar items now:
    // no custom background, no border, no divider. The system groups same-type
    // items onto one shared glass capsule and separates the two functional
    // groups with a `ToolbarSpacer` where it exists.

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Scope", selection: $scope) {
                ForEach(ModelScope.allCases) { item in
                    if let symbol = item.symbol {
                        Label(item.title, systemImage: symbol).tag(item)
                    } else {
                        Text(item.title).tag(item)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
            .labelsHidden()
            .controlSize(.small)
            .help("Show all models, only local ones, or only cloud ones")
        }

        // macOS 26+ only. Below it, the system's own inter-item spacing keeps
        // the two groups apart — a little tighter, never merged.
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(ModelSort.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelStyle(.titleAndIcon)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuIndicator(.hidden)
            .help("Sort the model list")
        }
    }
}

// MARK: - Groups

/// The three provider groups. One value owns the title, the privacy sentence and
/// the tile, so the hero card and the group header can never disagree about what
/// an OpenAI model looks like.
enum ModelGroup: String, Identifiable {
    case local, openAI, elevenLabs

    var id: String { rawValue }

    var provider: CloudProvider? {
        switch self {
        case .local: return nil
        case .openAI: return .openAI
        case .elevenLabs: return .elevenLabs
        }
    }

    var title: String {
        switch self {
        case .local: return "On this Mac"
        case .openAI: return "OpenAI"
        case .elevenLabs: return "ElevenLabs"
        }
    }

    /// Where the audio goes and who bills it — the two things a reader needs
    /// before picking anything in the group, said once per group instead of
    /// once per row.
    var subtitle: String {
        switch self {
        case .local:
            return "Audio never leaves this Mac. Free to run."
        case .openAI:
            return "Audio is sent to OpenAI. Usage is billed to your API key."
        case .elevenLabs:
            return "Audio is sent to ElevenLabs. Usage is billed to your API key."
        }
    }

    var tileSymbol: String {
        switch self {
        case .local: return "laptopcomputer"
        case .openAI: return "cloud.fill"
        case .elevenLabs: return "waveform"
        }
    }

    /// Matches the Cloud pane's provider tints, so the same provider wears the
    /// same colour in both panes.
    var tileTint: Color {
        switch self {
        case .local: return Palette.signalReady
        case .openAI: return Palette.accent
        case .elevenLabs: return Palette.badgeIndigo
        }
    }

    /// A model belongs to the group whose provider it names — and to `.local`
    /// when it names none.
    func contains(_ model: ModelDescriptor) -> Bool {
        model.backend.cloudProvider == provider
    }

    static func group(for model: ModelDescriptor) -> ModelGroup {
        guard let provider = model.backend.cloudProvider else { return .local }
        switch provider {
        case .openAI: return .openAI
        case .elevenLabs: return .elevenLabs
        }
    }
}

/// One group: a header row, then its models, all inside a single flush plate.
/// A plain `VStack` rather than a `LazyVStack` — there are at most 15 rows in
/// the whole pane, and lazy rows drop out of the animation when a sort reorders
/// them.
private struct ModelGroupPlate: View {
    let group: ModelGroup
    let models: [ModelDescriptor]
    @Bindable var registry: ModelRegistry
    let onShowCloudSettings: () -> Void

    var body: some View {
        Plate(.flush) {
            VStack(spacing: 0) {
                GroupHeaderRow(
                    group: group,
                    registry: registry,
                    onShowCloudSettings: onShowCloudSettings
                )
                // Full-bleed under the header: it separates the group's identity
                // from its contents, where the inset dividers below separate
                // peers.
                PlateDivider(leadingInset: 0)

                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    if index > 0 { PlateDivider() }
                    ModelRow(model: model, registry: registry)
                }
            }
        }
    }
}

private struct GroupHeaderRow: View {
    let group: ModelGroup
    @Bindable var registry: ModelRegistry
    let onShowCloudSettings: () -> Void
    @Environment(\.increaseContrast) private var increaseContrast

    var body: some View {
        HStack(alignment: .center, spacing: Space.s5) {
            ProviderIconTile(symbol: group.tileSymbol, tint: group.tileTint)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(group.title)
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                Text(group.subtitle)
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s5)

            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.s5)
        // `.contain`, not `.combine`: the trailing control is a button with a
        // popover, and it has to stay its own element to be reachable.
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var trailing: some View {
        if let provider = group.provider {
            if provider.hasAPIKey {
                StatusLabel(level: .ready, text: connectedText(provider))
            } else {
                AddAPIKeyButton(provider: provider, onShowCloudSettings: onShowCloudSettings)
            }
        } else if registry.totalDiskUsageBytes > 0 {
            // Moved here from the pane header: it is a fact about the local
            // group, and it was the only thing making the pane title a two-column
            // layout.
            Text("\(registry.totalDiskUsageBytes.formattedDiskSize) on disk")
                .typo(.captionMedium)
                .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                .fixedSize()
        }
    }

    private func connectedText(_ provider: CloudProvider) -> String {
        guard let suffix = provider.apiKeySuffix else { return "Connected" }
        return "Connected · …\(suffix)"
    }
}

// MARK: - Active model card

/// The pane's answer to "what am I using right now, and does it work". Static —
/// it is a readout, not a control, so it never hovers or presses; the only
/// interactive thing on it is the fix for a readiness problem.
private struct ActiveModelCard: View {
    @Bindable var registry: ModelRegistry
    let onShowCloudSettings: () -> Void
    @Environment(\.increaseContrast) private var increaseContrast

    var body: some View {
        if let model = registry.activeModel {
            let group = ModelGroup.group(for: model)
            Plate {
                HStack(alignment: .top, spacing: Space.s5) {
                    ProviderIconTile(symbol: group.tileSymbol, tint: group.tileTint)

                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Active model")
                            .typo(.micro)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                        Text(model.sectionedDisplayName)
                            .typo(.title)
                            .foregroundStyle(Palette.ink)
                        // The notes are the only text that explains how two
                        // near-identical models differ. On the hero they get a
                        // full line instead of a tooltip.
                        Text(model.notes)
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(ModelFacts.facets(for: model, readiness: registry.readiness(for: model.id)))
                            .typo(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                    }

                    Spacer(minLength: Space.s5)

                    readiness(for: model)
                        .controlSize(.small)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func readiness(for model: ModelDescriptor) -> some View {
        if let provider = model.backend.cloudProvider {
            // Never `registry.readiness(for:)` for a cloud model: the registry
            // writes `.preparing` to one before every dictation. Having the key
            // is the whole of cloud readiness.
            if provider.hasAPIKey {
                StatusLabel(level: .ready, text: "Connected")
            } else {
                AddAPIKeyButton(provider: provider, onShowCloudSettings: onShowCloudSettings)
            }
        } else {
            localReadiness(for: model)
        }
    }

    @ViewBuilder
    private func localReadiness(for model: ModelDescriptor) -> some View {
        switch registry.readiness(for: model.id) {
        case .notInstalled:
            HStack(spacing: Space.s4) {
                Text(ModelFacts.approximateSize(model))
                    .typo(.caption)
                    .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                Button("Download") {
                    Task { await registry.prepareModel(id: model.id) }
                }
                .buttonStyle(.bordered)
            }

        case .preparing(let fraction, let message):
            PreparingIndicator(fraction: fraction, message: message)

        case .installed:
            StatusLabel(level: .ready, text: "Installed")

        case .failed(let message):
            HStack(spacing: Space.s4) {
                StatusLabel(level: .error, text: "Failed")
                    .help(message)
                Button("Retry") {
                    Task { await registry.prepareModel(id: model.id) }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Row

private struct ModelRow: View {
    /// 18pt for both indicator states, so the ring and the check occupy exactly
    /// the same box and the title never shifts when selection moves.
    private static let indicatorSize: CGFloat = 18

    let model: ModelDescriptor
    @Bindable var registry: ModelRegistry
    @State private var isHovering = false
    @State private var isShowingDetails = false
    @State private var isConfirmingDelete = false
    @Environment(\.motion) private var motion
    @Environment(\.increaseContrast) private var increaseContrast

    private var isActive: Bool { registry.activeModelId == model.id }
    private var readiness: ModelReadiness { registry.readiness(for: model.id) }
    private var name: String { model.sectionedDisplayName }

    var body: some View {
        HStack(spacing: Space.s5) {
            // The select target and nothing else. Every trailing control sits
            // outside this button, so clicking Download or ⋯ can't also change
            // which model dictation uses.
            Button {
                registry.setActive(model.id)
            } label: {
                selectLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Use for dictation")
            .accessibilityAddTraits(isActive ? [.isSelected] : [])

            trailingControls
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(rowFill)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(motion.hover, value: isHovering)
        .contextMenu { contextMenuItems }
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

    /// Active gets the accent wash; hover gets the plate lift. The enclosing
    /// flush plate clips, so the first and last rows round their own corners.
    private var rowFill: Color {
        if isActive { return Palette.accent.opacity(0.08) }
        if isHovering { return Palette.plateHover(increaseContrast: increaseContrast) }
        return .clear
    }

    // MARK: The select target

    private var selectLabel: some View {
        HStack(spacing: Space.s5) {
            selectionIndicator

            VStack(alignment: .leading, spacing: Space.s1) {
                // Title and badges flow: inline while they fit, badges wrap to
                // the next line instead of truncating the title.
                BadgeFlow(hSpacing: Space.s3, vSpacing: Space.s2) {
                    Text(name)
                        .typo(.headline)
                        .foregroundStyle(isActive ? Palette.accent : Palette.ink)
                        .lineLimit(1)
                    badges
                }
                Text(ModelFacts.facets(for: model, readiness: readiness))
                    .typo(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(ModelFacts.detailsText(for: model))
            }
            // Claim all free row width — otherwise the column settles at its
            // ideal size and the leftover becomes a blank gap while the title
            // truncates.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The radio control that replaced the accent bar, the ACTIVE chip and the
    /// invisible tap gesture. One affordance, visible at rest, in the position
    /// every list in macOS puts a selection mark.
    private var selectionIndicator: some View {
        Group {
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Palette.accent)
            } else {
                Circle()
                    .strokeBorder(
                        isHovering
                            ? Palette.inkMuted
                            : Palette.inkFaint(increaseContrast: increaseContrast),
                        lineWidth: 1
                    )
            }
        }
        .frame(width: Self.indicatorSize, height: Self.indicatorSize)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var badges: some View {
        if model.isRealtime { RealtimeBadge() }
        if let chip = ModelBadges.editorial(for: model) {
            Chip(text: chip.text, symbol: chip.symbol, tint: chip.tint)
        }
    }

    // MARK: Trailing controls

    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: Space.s4) {
            // Cloud rows carry no readiness control at all — their group header
            // owns the connection state, and repeating it 9 times was most of
            // what made the old list unreadable.
            if !model.isCloud { localReadinessControl }

            detailsButton

            if readiness.isInstalled, !model.isCloud { moreMenu }
        }
    }

    private var detailsButton: some View {
        Button {
            isShowingDetails = true
        } label: {
            Image(systemName: "info.circle")
                .font(Typo.headline)
                .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Details for \(name)")
        .help("Details")
        .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
            ModelDetailsPopover(model: model)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Delete from Mac…", role: .destructive) { isConfirmingDelete = true }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(Typo.headline)
                .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More actions for \(name)")
    }

    @ViewBuilder
    private var localReadinessControl: some View {
        switch readiness {
        case .notInstalled:
            Button("Download") {
                Task { await registry.prepareModel(id: model.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .preparing(let fraction, let message):
            PreparingIndicator(fraction: fraction, message: message)

        case .installed:
            StatusLabel(level: .ready, text: "Installed")

        case .failed(let message):
            HStack(spacing: Space.s4) {
                StatusLabel(level: .error, text: "Failed")
                    .help(message)
                Button("Retry") {
                    Task { await registry.prepareModel(id: model.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: Context menu and accessibility

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Use for Dictation") { registry.setActive(model.id) }
            .disabled(isActive)
        Button("Details…") { isShowingDetails = true }

        if !model.isCloud {
            Divider()
            switch readiness {
            case .notInstalled, .failed:
                Button("Download") {
                    Task { await registry.prepareModel(id: model.id) }
                }
            case .installed:
                Button("Delete from Mac…", role: .destructive) { isConfirmingDelete = true }
            case .preparing:
                EmptyView()
            }
        }
    }

    /// The facets a sighted reader gets from the meta line, plus the readiness
    /// word they get from the trailing control — which VoiceOver would otherwise
    /// reach only after the row itself.
    private var accessibilityValue: String {
        ModelFacts.facets(for: model, readiness: readiness) + ", " + readinessWord
    }

    private var readinessWord: String {
        if let provider = model.backend.cloudProvider {
            return provider.hasAPIKey ? "Connected" : "Needs API key"
        }
        switch readiness {
        case .notInstalled: return "Not downloaded"
        case .preparing: return "Downloading"
        case .installed: return "Installed"
        case .failed: return "Download failed"
        }
    }
}

// MARK: - Shared readiness pieces

/// The compact download indicator: a 120pt bar, the stage message, and the
/// percentage in the machine register so it doesn't jitter as it counts.
private struct PreparingIndicator: View {
    let fraction: Double
    let message: String
    @Environment(\.increaseContrast) private var increaseContrast

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.s2) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .frame(width: 120)
            HStack(spacing: Space.s3) {
                Text(message)
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
                Text("\(Int(fraction * 100))%")
                    .typo(.mono)
                    .contentTransition(.numericText())
                    .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The warn-tinted "Add API key →" affordance and the popover behind it. Owns
/// its own presentation state so the hero card and a group header can each
/// carry one without sharing a flag.
///
/// It never calls `setActive`: both of its call sites are about a provider, not
/// a model — the hero's model is already active, and a header speaks for every
/// row under it.
private struct AddAPIKeyButton: View {
    let provider: CloudProvider
    let onShowCloudSettings: () -> Void
    @State private var isShowingKeyEntry = false

    var body: some View {
        Button {
            isShowingKeyEntry = true
        } label: {
            HStack(spacing: Space.s2) {
                Text("Add API key")
                Image(systemName: "arrow.right")
                    .font(Typo.micro)
            }
            .typo(.captionMedium)
            .foregroundStyle(Palette.signalWarn)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.signalWarn.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(provider.displayName) API key")
        .help("Add your API key without leaving this list")
        .popover(isPresented: $isShowingKeyEntry, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text("\(provider.displayName) API key")
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)

                APIKeyEntryView(config: .forProvider(provider)) {
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
    }
}

// MARK: - Details popover

/// Everything the row deliberately doesn't print: the notes, the raw word error
/// rates with their benchmarks, and where the quality score and the price came
/// from. A popover rather than a tooltip because these are sentences, and
/// because a tooltip can't be reached from the keyboard.
private struct ModelDetailsPopover: View {
    let model: ModelDescriptor
    @Environment(\.increaseContrast) private var increaseContrast

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(model.sectionedDisplayName)
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                Text(model.notes)
                    .typo(.body)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let benchmarkLines = ModelFacts.benchmarkLines(for: model)
            if !benchmarkLines.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Benchmarks")
                        .typo(.micro)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                    ForEach(Array(benchmarkLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Space.s2) {
                Text(ModelFacts.qualityScale)
                    .typo(.caption)
                    .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                    .fixedSize(horizontal: false, vertical: true)
                if let priceHelp = ModelFacts.priceProvenance(for: model) {
                    Text(priceHelp)
                        .typo(.caption)
                        .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Space.s6)
        .frame(width: 340, alignment: .leading)
    }
}

// MARK: - Facts

/// Every string the pane derives from a `ModelDescriptor`, in one place. The
/// row's tooltip, the details popover and the hero card all print the same
/// numbers; assembling them three times is how two of them go stale.
private enum ModelFacts {

    /// The row's one meta line: `Quality 8.9 · $0.27/hr · 99+ languages`, or
    /// `Quality 8.7 · 483 MB · 25 European languages`.
    ///
    /// "Cloud"/"Local" and "Free" are gone from it — the group header above the
    /// row already said both, and saying them again on 14 rows is what made the
    /// line a monospaced wall. What is left is exactly the axes two rows in the
    /// same group differ on.
    ///
    /// Raw word error rates stay in the details popover rather than earning a
    /// segment: local and cloud models are measured on different benchmarks, and
    /// two benchmarks' percentages in one column would invite precisely the
    /// comparison they don't support. The quality score is the comparable
    /// number, because it is expressed against a model both benchmarks measure.
    static func facets(for model: ModelDescriptor, readiness: ModelReadiness) -> String {
        var parts = [quality(model)]
        if model.isCloud {
            if let price = price(model) { parts.append(price) }
        } else if let size = size(model, readiness: readiness) {
            parts.append(size)
        }
        parts.append(ModelBadges.languagesLabel(model.languages))
        return parts.joined(separator: " · ")
    }

    /// "Quality 8.9" — the score derived from published word error rates. "≈"
    /// marks a score resting on indirect evidence rather than the model's own
    /// Artificial Analysis figure; a model nothing has benchmarked prints
    /// "Quality —" rather than inventing a number. The "/10" the old line
    /// carried moved to the popover's scale sentence, which explains the scale
    /// instead of just asserting it.
    static func quality(_ model: ModelDescriptor) -> String {
        guard let quality = model.quality else { return "Quality —" }
        let prefix = model.isQualityApproximate ? "≈" : ""
        return "Quality \(prefix)\(String(format: "%.1f", quality))"
    }

    /// A model the catalog has no price for prints no price segment at all
    /// rather than a guess — see `ModelDescriptor.pricePerHourUSD`. Local models
    /// price at 0, and "Free" is already in their group subtitle.
    static func price(_ model: ModelDescriptor) -> String? {
        guard let price = model.pricePerHourUSD, price > 0 else { return nil }
        return String(format: "$%.2f/hr", price)
    }

    /// The real on-disk size once installed, the catalog's estimate before.
    /// Cloud models occupy no disk, so they print no size segment.
    static func size(_ model: ModelDescriptor, readiness: ModelReadiness) -> String? {
        guard !model.isCloud else { return nil }
        if case .installed(let bytes) = readiness { return bytes.formattedDiskSize }
        return approximateSize(model)
    }

    static func approximateSize(_ model: ModelDescriptor) -> String {
        "~\((Int64(model.approxSizeMB) * 1_000_000).formattedDiskSize)"
    }

    /// One line per measurement. Each names its own benchmark and prints Whisper
    /// Large v3's score on that benchmark beside it, because that is the only
    /// figure that makes one leaderboard's percentage mean anything next to
    /// another's. A measurement's caveat gets its own line.
    static func benchmarkLines(for model: ModelDescriptor) -> [String] {
        var lines: [String] = []
        for measurement in model.benchmarks {
            let percent = String(format: "%.1f", measurement.percent)
            let reference = String(format: "%.1f", measurement.benchmark.whisperLargeV3Percent)
            var line = "\(percent)% WER on \(benchmarkPhrase(measurement.benchmark)) "
                + "— Whisper Large v3: \(reference)%."
            if measurement.isEstimate { line += " Estimate." }
            lines.append(line)
            if let note = measurement.note { lines.append(note) }
        }
        return lines
    }

    static let qualityScale = "Quality: Whisper Large v3 is 8.0; half its errors scores 10, "
        + "twice its errors scores 5."

    /// Who charges the price, and the reminder that it is never this app: cloud
    /// usage bills to the user's own API key. Local models cost nothing, so they
    /// say so instead of naming a provider.
    static func priceProvenance(for model: ModelDescriptor) -> String? {
        guard model.pricePerHourUSD != nil else { return nil }
        guard let provider = model.backend.cloudProvider?.displayName else {
            return "Free — runs on this Mac, no per-minute cost."
        }
        return "Price is \(provider)'s list price per hour of audio (September 2026), "
            + "billed by \(provider) to your own API key. Approximate."
    }

    /// The popover's content as one tooltip string, for the row's meta line.
    static func detailsText(for model: ModelDescriptor) -> String {
        var lines = [model.notes]
        lines.append(contentsOf: benchmarkLines(for: model))
        lines.append(qualityScale)
        if let priceHelp = priceProvenance(for: model) { lines.append(priceHelp) }
        return lines.joined(separator: "\n")
    }

    /// The benchmark name as it reads mid-sentence. Open ASR needs the "(English
    /// average)" qualifier spelled out — it is the one place the figure's scope
    /// is narrower than the model's.
    private static func benchmarkPhrase(_ benchmark: WERMeasurement.Benchmark) -> String {
        switch benchmark {
        case .openASRLeaderboard:
            return "the \(benchmark.displayName) (English average)"
        case .artificialAnalysis:
            return benchmark.displayName
        }
    }
}

// MARK: - Subcomponents

/// Left-aligned flow for the title line: everything on one line while it
/// fits, overflowing badges wrap to following lines instead of squeezing or
/// truncating the title.
private struct BadgeFlow: Layout {
    var hSpacing: CGFloat
    var vSpacing: CGFloat

    nonisolated func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            size.width = min(size.width, maxWidth)
            if x > 0, x + hSpacing + size.width > maxWidth {
                x = 0
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            if x > 0 { x += hSpacing }
            x += size.width
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    nonisolated func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width
        var rows: [[(view: LayoutSubview, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            size.width = min(size.width, maxWidth)
            if x > 0, x + hSpacing + size.width > maxWidth {
                rows.append([])
                x = 0
            }
            if x > 0 { x += hSpacing }
            x += size.width
            rows[rows.count - 1].append((view, size))
        }
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map(\.size.height).max() ?? 0
            var px = bounds.minX
            for (view, size) in row {
                view.place(
                    at: CGPoint(x: px, y: y + (rowHeight - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                px += size.width + hSpacing
            }
            y += rowHeight + vSpacing
        }
    }
}

/// A subtle rounded editorial chip (symbol + short label), tinted at low opacity.
private struct Chip: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: Space.s1) {
            Image(systemName: symbol)
                .font(Typo.micro)
            Text(text)
                .typo(.micro)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(tint)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s1)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// Marks a real-time streaming model (text appears as you speak). A softly
/// pulsing dot + "LIVE".
private struct RealtimeBadge: View {
    @State private var pulsing = false
    @Environment(\.motion) private var motion

    var body: some View {
        HStack(spacing: Space.s2) {
            Circle()
                .fill(Palette.signalWarn)
                .frame(width: 5, height: 5)
                .opacity(motion.repeatsAllowed ? (pulsing ? 1.0 : 0.35) : 0.85)
            Text("LIVE")
                .typo(.micro)
        }
        .foregroundStyle(Palette.signalWarn)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s1)
        .background(Capsule().fill(Palette.signalWarn.opacity(0.15)))
        .onAppear {
            guard motion.repeatsAllowed else { return }
            withAnimation(.smooth(duration: 1.1).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Editorial badge logic

/// Presentation-only helpers that derive editorial chips and language labels
/// from the static catalog. Kept in the Settings layer so `ModelRegistry`
/// stays free of UI concerns.
private enum ModelBadges {
    /// The highest-scoring local model. When the winner is also the Recommended
    /// model, the "at most one chip" priority in `editorial(_:)` shows only
    /// "Recommended" — the honest outcome rather than double-labelling one row.
    static let mostAccurateLocalId: String? = highestQualityId { !$0.isCloud }

    /// The highest-scoring cloud model, used for the "Most accurate" chip.
    static let mostAccurateCloudId: String? = highestQualityId(\.isCloud)

    /// One "Fastest" per cohort, not one per top-speed model. Speed saturates at
    /// 10 — six models in the catalog are tied there — so the old `speed == 10`
    /// test printed the chip on three cloud rows at once, which is three ways of
    /// saying nothing. The tie breaks on quality: of the fastest models, the one
    /// that is also the most accurate is the one worth pointing at.
    static let fastestLocalId: String? = fastestId { !$0.isCloud }

    static let fastestCloudId: String? = fastestId(\.isCloud)

    /// `max(by:)` keeps the first of equal maxima, so a tie falls to whichever
    /// model the catalog lists first — the curated order still breaks ties.
    private static func highestQualityId(
        _ isIncluded: (ModelDescriptor) -> Bool
    ) -> String? {
        ModelCatalog.all
            .filter { isIncluded($0) && $0.quality != nil }
            .max { ($0.quality ?? 0) < ($1.quality ?? 0) }?
            .id
    }

    /// The most accurate of the cohort's fastest models — and only if it is
    /// accurate enough to recommend at all. A model nobody should pick doesn't
    /// get a chip for being quick about it.
    private static func fastestId(
        _ isIncluded: (ModelDescriptor) -> Bool
    ) -> String? {
        let cohort = ModelCatalog.all.filter(isIncluded)
        guard let topSpeed = cohort.map(\.speed).max() else { return nil }
        let fastest = cohort
            .filter { $0.speed == topSpeed }
            .max { ($0.quality ?? 0) < ($1.quality ?? 0) }
        guard let fastest, (fastest.quality ?? 0) >= 8 else { return nil }
        return fastest.id
    }

    /// At most one editorial chip per model. Priority: Recommended, then Most
    /// accurate, then Fastest — and a model that wins an earlier one simply
    /// keeps it. The Fastest chip is never handed down to a runner-up, because
    /// the runner-up is not the fastest.
    static func editorial(for model: ModelDescriptor) -> (text: String, symbol: String, tint: Color)? {
        if model.id == "parakeet-tdt-v3" {
            return ("Recommended", "sparkles", Palette.accent)
        }
        if model.id == mostAccurateLocalId || model.id == mostAccurateCloudId {
            return ("Most accurate", "target", Palette.badgeIndigo)
        }
        if model.id == fastestLocalId || model.id == fastestCloudId {
            return ("Fastest", "bolt.fill", Palette.signalWarn)
        }
        return nil
    }

    /// The `languages` field is a free string ("99", "90+", "25 European languages").
    /// Append " languages" only when it's a bare count so mixed strings read
    /// naturally.
    static func languagesLabel(_ languages: String) -> String {
        let numericish = languages.contains(where: \.isNumber)
            && languages.allSatisfy { $0.isNumber || $0 == "+" }
        return numericish ? "\(languages) languages" : languages
    }
}
