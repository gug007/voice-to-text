import AppKit
import SwiftUI

/// The "Models" settings pane: a sectioned, editorialized list of local and
/// cloud transcription models. Local models live under "On this Mac", cloud
/// models under "Cloud". The active model gets an accent-gradient treatment;
/// non-active rows lift on hover and expose a "Use" affordance.
struct ModelsPane: View {
    @Bindable var registry: ModelRegistry
    var onShowCloudSettings: () -> Void = {}
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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                HStack(spacing: 12) {
                    ScopePicker(scope: $scope)
                    Spacer()
                    HStack(spacing: 8) {
                        Text("Sort by")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        MinimalDropdown(
                            selection: $sort,
                            sections: [
                                DropdownSection(items: ModelSort.allCases.map {
                                    DropdownItem(value: $0, title: $0.title)
                                })
                            ],
                            popupWidth: 150
                        )
                    }
                }

                VStack(spacing: 8) {
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
            .padding(.horizontal, 36)
            .padding(.vertical, 36)
            // Selection changes animate the accent treatment across the whole
            // list rather than per-row, so borders/glow cross-fade in one motion.
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: registry.activeModelId)
        }
        .onAppear { registry.refreshInstalledState() }
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
        HStack(spacing: 5) {
            Image(systemName: "internaldrive")
                .font(.system(size: 10, weight: .semibold))
            Text("\(registry.totalDiskUsageBytes.formattedDiskSize) on disk")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

}

/// Minimal capsule filter for the model list: All / On this Mac / Cloud.
private struct ScopePicker: View {
    @Binding var scope: ModelsPane.ModelScope

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ModelsPane.ModelScope.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        scope = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = item.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 10, weight: .medium))
                        }
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(scope == item ? Color.primary : Color.secondary)
                    .background(
                        Capsule().fill(scope == item
                                       ? Color.primary.opacity(0.09)
                                       : Color.clear)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule().strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

// MARK: - Row

private struct ModelRow: View {
    let model: ModelDescriptor
    @Bindable var registry: ModelRegistry
    let onShowCloudSettings: () -> Void
    @Bindable private var keyStore = OpenAIAPIKeyStore.shared
    @State private var hovered = false

    private var isActive: Bool { registry.activeModelId == model.id }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ProviderIconTile(isCloud: model.isCloud)

            VStack(alignment: .leading, spacing: 6) {
                // Title and badges flow: inline while they fit, badges wrap
                // to the next line instead of truncating the title.
                BadgeFlow(hSpacing: 8, vSpacing: 5) {
                    titleText
                    badges
                }
                Text(model.notes)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    CapsuleGauge(
                        label: "Quality",
                        value: model.quality,
                        tint: .accentColor,
                        annotation: werAnnotation,
                        annotationHelp: werAnnotation == nil ? nil
                            : "Word error rate — Open ASR Leaderboard (English average). Lower is better."
                    )
                    CapsuleGauge(label: "Speed", value: model.speed, tint: .teal)
                    languagesChip
                }
                .padding(.top, 2)
            }
            // Claim all free row width — otherwise the column settles at its
            // ideal size and the leftover becomes a blank gap while the title
            // truncates.
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                readinessControl
                if let size = displaySize {
                    Text(size)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fillColor)
                // Glow lives on the card shape, not the row, so text and
                // controls inside don't inherit a tinted shadow.
                .shadow(color: isActive ? Color.accentColor.opacity(0.22) : .clear, radius: 10, y: 3)
        )
        .overlay(rowBorder)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) { hovered = h }
        }
    }

    private var fillColor: Color {
        if isActive { return Color.accentColor.opacity(0.12) }
        if hovered { return Color(nsColor: .controlBackgroundColor).opacity(0.9) }
        return Color(nsColor: .controlBackgroundColor).opacity(0.6)
    }

    @ViewBuilder
    private var rowBorder: some View {
        if isActive {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovered ? 0.14 : 0.06))
        }
    }

    private var titleText: some View {
        Text(model.sectionedDisplayName)
            .font(.system(size: 14, weight: .semibold))
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
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Active")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.accentColor.opacity(0.15))
        )
    }

    private var languagesChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.system(size: 9, weight: .semibold))
            Text(ModelBadges.languagesLabel(model.languages))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .fixedSize()
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

    @ViewBuilder
    private var cloudReadinessControl: some View {
        if keyStore.hasKey {
            StatusDot(color: .green, label: "Connected")
        } else {
            Button {
                onShowCloudSettings()
            } label: {
                HStack(spacing: 3) {
                    Text("Add API key")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
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
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                HStack(spacing: 6) {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(Int(fraction * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

        case .installed:
            HStack(spacing: 8) {
                StatusDot(color: .green, label: "Installed")
                Button {
                    registry.deleteModel(id: model.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
            .tint(.red)
        }
    }
}

// MARK: - Subcomponents

/// A small labeled capsule bar showing a 1–10 rating as a fill fraction. Track
/// uses an opacity-based tint so it reads in both light and dark mode.
///
/// The bar fill always reflects the static `value` (visual continuity). Two
/// optional overlays surface benchmark data without disturbing the bar:
/// `valueText` replaces the numeric readout (e.g. a measured "28×"), and
/// `annotation` appends a quieter trailing note (e.g. "6.3% WER").
private struct CapsuleGauge: View {
    let label: String
    let value: Int
    let tint: Color
    var annotation: String? = nil
    var annotationHelp: String? = nil

    private var fraction: Double { Double(min(max(value, 0), 10)) / 10.0 }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(width: 56, height: 5)
            Text("\(value)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            if let annotation {
                Text(annotation)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .help(annotationHelp ?? "")
            }
        }
        .fixedSize()
    }
}

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
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

/// Marks a real-time streaming model (text appears as you speak). A softly
/// pulsing dot + "LIVE", styled to match `activeBadge`.
private struct RealtimeBadge: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.orange)
                .frame(width: 5, height: 5)
                .opacity(pulsing ? 1.0 : 0.35)
            Text("LIVE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
        }
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.orange.opacity(0.15))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
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
            return ("Recommended", "sparkles", .accentColor)
        }
        if model.id == mostAccurateLocalId || model.id == mostAccurateCloudId {
            return ("Most accurate", "target", .indigo)
        }
        if model.speed == 10 && model.quality >= 8 {
            return ("Fastest", "bolt.fill", .orange)
        }
        return nil
    }

    /// The `languages` field is a free string ("99", "90+", "25 European + JA").
    /// Append " languages" only when it's a bare count so mixed strings read
    /// naturally.
    static func languagesLabel(_ languages: String) -> String {
        let numericish = languages.contains(where: \.isNumber)
            && languages.allSatisfy { $0.isNumber || $0 == "+" }
        return numericish ? "\(languages) languages" : languages
    }
}
