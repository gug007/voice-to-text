import AppKit
import SwiftUI

/// The "Models" settings pane: a sectioned, editorialized list of local and
/// cloud transcription models. Local models live under "On this Mac", cloud
/// models under "Cloud". The active model gets an accent-gradient treatment;
/// non-active rows lift on hover and expose a "Use" affordance.
struct ModelsPane: View {
    @Bindable var registry: ModelRegistry
    var onShowCloudSettings: () -> Void = {}
    @Environment(\.motion) private var motion
    @Environment(\.increaseContrast) private var increaseContrast
    @State private var scope: ModelScope = .all

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
    }

    @State private var sort: ModelSort = .quality

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

    /// One mixed list — the scope filter and sort control the order; the tile
    /// icon (laptop vs cloud) carries the local/cloud distinction per row.
    private var visibleModels: [ModelDescriptor] {
        let filtered: [ModelDescriptor]
        switch scope {
        case .all: filtered = ModelCatalog.all
        case .local: filtered = ModelCatalog.all.filter { !$0.isCloud }
        case .cloud: filtered = ModelCatalog.all.filter { $0.isCloud }
        }
        return sorted(filtered)
    }

    /// Swift's `sorted(by:)` is stable, so ties keep their curated catalog order.
    private func sorted(_ models: [ModelDescriptor]) -> [ModelDescriptor] {
        switch sort {
        case .featured:
            return models
        case .quality:
            // `quality` is recalibrated to match WER ordering, so it's the
            // primary key; the benchmark WER (lower is better) breaks ties into
            // a total, consistent order when both models have leaderboard data.
            return models.sorted {
                if $0.quality != $1.quality { return $0.quality > $1.quality }
                let l = $0.benchmarkWER ?? .greatestFiniteMagnitude
                let r = $1.benchmarkWER ?? .greatestFiniteMagnitude
                return l < r
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
            header

            VStack(spacing: Space.s4) {
                ForEach(visibleModels) { model in
                    ModelRow(
                        model: model,
                        registry: registry,
                        onShowCloudSettings: onShowCloudSettings
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { registry.setActive(model.id) }
                }
            }
        }
        // Selection changes animate the accent treatment across the whole
        // list rather than per-row, so every row's tint moves in one motion.
        .animation(motion.select, value: registry.activeModelId)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            PaneHeader(
                title: "Models",
                subtitle: "Pick the model you want to use for dictation."
            )
            Spacer()
            if registry.totalDiskUsageBytes > 0 {
                diskUsageChip
            }
        }
    }

    private var diskUsageChip: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "internaldrive")
                .font(Typo.micro)
            Text("\(registry.totalDiskUsageBytes.formattedDiskSize) on disk")
                .typo(.mono)
        }
        .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(Capsule().fill(Palette.ink.opacity(0.06)))
    }

}

// `ScopePicker` — the hand-rolled capsule segmented control that used to sit in
// the pane's first row — is gone. It is a system `Picker(.segmented)` in the
// toolbar now, which is one fewer bespoke control to keep in sync with the
// system's control metrics.

// MARK: - Row

private struct ModelRow: View {
    /// The 56pt model row of the spec: a 34pt tile, one title line and one
    /// monospaced meta line. The two `CapsuleGauge`s and the notes paragraph
    /// they sat under are gone — a 1–10 bar told the user nothing they could
    /// act on, where "Local · 632 MB · 7.8% WER · 99 languages" is the axis
    /// eight near-identical rows actually differ on.
    static let minHeight: CGFloat = 56

    let model: ModelDescriptor
    @Bindable var registry: ModelRegistry
    let onShowCloudSettings: () -> Void
    @Bindable private var openAIKeys = OpenAIAPIKeyStore.shared
    @Bindable private var elevenLabsKeys = ElevenLabsAPIKeyStore.shared
    @Environment(\.increaseContrast) private var increaseContrast

    private var isActive: Bool { registry.activeModelId == model.id }

    var body: some View {
        Plate(isInteractive: true, padding: 0) {
            rowContent
                // Both the tint wash and the selection bar live inside the
                // plate's content, so the plate's own clip shape keeps them
                // concentric instead of squaring off its corners.
                .background(isActive ? Palette.accent.opacity(0.08) : Color.clear)
                .overlay(alignment: .leading) { selectionBar }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: Space.s5) {
            ProviderIconTile(isCloud: model.isCloud)

            VStack(alignment: .leading, spacing: Space.s1) {
                // Title and badges flow: inline while they fit, badges wrap
                // to the next line instead of truncating the title.
                BadgeFlow(hSpacing: Space.s3, vSpacing: Space.s2) {
                    titleText
                    badges
                }
                Text(metaLine)
                    .typo(.mono)
                    .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(metaLineHelp)
            }
            // Claim all free row width — otherwise the column settles at its
            // ideal size and the leftover becomes a blank gap while the title
            // truncates.
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: Space.s5)

            readinessControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: Self.minHeight)
    }

    /// The active row's 3 × 40 accent bar. The 1.5pt gradient border and the
    /// accent glow are gone: tint carries the meaning, decoration doesn't.
    @ViewBuilder
    private var selectionBar: some View {
        if isActive {
            Capsule()
                .fill(Palette.accent)
                .frame(width: 3, height: 40)
                .padding(.leading, Space.s2)
        }
    }

    private var titleText: some View {
        Text(model.sectionedDisplayName)
            .typo(.headline)
            .foregroundStyle(isActive ? Palette.accent : Palette.ink)
            .lineLimit(1)
    }

    @ViewBuilder
    private var badges: some View {
        if model.isRealtime { RealtimeBadge() }
        if let chip = ModelBadges.editorial(for: model) {
            Chip(text: chip.text, symbol: chip.symbol, tint: chip.tint)
        }
        if isActive { activeBadge }
    }

    private var activeBadge: some View {
        HStack(spacing: Space.s1) {
            Image(systemName: "checkmark")
                .font(Typo.micro)
            Text("Active")
                .typo(.micro)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(Palette.accent)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s1)
        .background(Capsule().fill(Palette.accent.opacity(0.14)))
    }

    // MARK: The meta line

    /// The one Mono 11 line that replaced two gauges, a globe chip and a notes
    /// paragraph: `Local · 632 MB · 7.8% WER · 99 languages`, or
    /// `Cloud · 99+ languages`.
    ///
    /// Every segment comes from a field `ModelDescriptor` actually carries. The
    /// spec's per-minute cloud price has no field behind it, so it is omitted
    /// rather than invented; cloud models likewise carry no `benchmarkWER`
    /// (there is no comparable public leaderboard) and no on-disk size.
    private var metaLine: String {
        var parts = [model.isCloud ? "Cloud" : "Local"]
        if let displaySize { parts.append(displaySize) }
        if let werAnnotation { parts.append(werAnnotation) }
        parts.append(ModelBadges.languagesLabel(model.languages))
        return parts.joined(separator: " · ")
    }

    /// The descriptive notes the row no longer has the height to print, plus
    /// the WER provenance the gauge's annotation used to carry.
    private var metaLineHelp: String {
        guard werAnnotation != nil else { return model.notes }
        return model.notes
            + "\nWord error rate — Open ASR Leaderboard (English average). Lower is better."
    }

    /// "6.3% WER" for models with leaderboard data, else nil.
    private var werAnnotation: String? {
        guard let wer = model.benchmarkWER else { return nil }
        return String(format: "%.1f%% WER", wer)
    }

    private var displaySize: String? {
        if model.isCloud { return nil }
        if case .installed(let bytes) = registry.readiness(for: model.id) {
            return bytes.formattedDiskSize
        }
        let approx = Int64(model.approxSizeMB) * 1_000_000
        return "~\(approx.formattedDiskSize)"
    }

    // MARK: Readiness controls (right)

    @ViewBuilder
    private var readinessControl: some View {
        if model.isCloud {
            cloudReadinessControl
        } else {
            localReadinessControl
        }
    }

    /// Whether the provider that owns THIS row has a key.
    ///
    /// The row used to read `OpenAIAPIKeyStore.shared` for every cloud model, so
    /// an OpenAI-only key reported the ElevenLabs row as "Connected" and the
    /// first dictation with it failed at the network boundary. Readiness now
    /// keys off `model.backend.cloudProvider`, which is the only thing that
    /// knows who the row belongs to.
    private var cloudProviderHasKey: Bool {
        switch model.backend.cloudProvider {
        case .openAI: return openAIKeys.hasKey
        case .elevenLabs: return elevenLabsKeys.hasKey
        case nil: return false
        }
    }

    @ViewBuilder
    private var cloudReadinessControl: some View {
        if cloudProviderHasKey {
            StatusLabel(level: .ready, text: "Connected")
        } else {
            Button {
                onShowCloudSettings()
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
            .help("Open Cloud settings to add your API key")
        }
    }

    @ViewBuilder
    private var localReadinessControl: some View {
        switch registry.readiness(for: model.id) {
        case .notInstalled:
            Button("Download") {
                Task { await registry.prepareModel(id: model.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .preparing(let fraction, let message):
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

        case .installed:
            HStack(spacing: Space.s4) {
                StatusLabel(level: .ready, text: "Installed")
                Button {
                    registry.deleteModel(id: model.id)
                } label: {
                    Image(systemName: "trash")
                        .font(Typo.captionMedium)
                        .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.plain)
                .help("Delete model from disk")
            }

        case .failed:
            Button("Retry") {
                Task { await registry.prepareModel(id: model.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Palette.signalWarn)
        }
    }
}

// MARK: - Subcomponents

// `CapsuleGauge` — the "Quality 8 / Speed 7" bar pair — is deleted along with
// its last call site. A 1–10 bar with no units was the least actionable thing
// on the row; the Mono 11 meta line prints the numbers those bars were a
// picture of (size, measured WER, language count).

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
/// pulsing dot + "LIVE", styled to match `activeBadge`.
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
    /// The most accurate local model by benchmark WER (lower is better). When
    /// this is also the Recommended model (as with parakeet, which leads on
    /// WER), the "at most one chip" priority in `editorial(_:)` shows only
    /// "Recommended" — so no separate local "Most accurate" chip appears, which
    /// is the honest outcome rather than double-labelling the same model.
    static let mostAccurateLocalId: String? = ModelCatalog.all
        .filter { !$0.isCloud && $0.benchmarkWER != nil }
        .min { ($0.benchmarkWER ?? .greatestFiniteMagnitude) < ($1.benchmarkWER ?? .greatestFiniteMagnitude) }?
        .id

    /// The highest-quality cloud model, used for the "Most accurate" chip.
    static let mostAccurateCloudId: String? = ModelCatalog.all
        .filter { $0.isCloud }
        .max { $0.quality < $1.quality }?.id

    /// At most one editorial chip per model. Priority: Recommended, then Most
    /// accurate, then Fastest.
    static func editorial(for model: ModelDescriptor) -> (text: String, symbol: String, tint: Color)? {
        if model.id == "parakeet-tdt-v3" {
            return ("Recommended", "sparkles", Palette.accent)
        }
        if model.id == mostAccurateLocalId || model.id == mostAccurateCloudId {
            return ("Most accurate", "target", Palette.badgeIndigo)
        }
        if model.speed == 10 && model.quality >= 8 {
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
