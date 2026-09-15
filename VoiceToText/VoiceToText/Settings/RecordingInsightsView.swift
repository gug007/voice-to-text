import AppKit
import SwiftUI

/// Everything the AI-insight layer of a recording row draws: the
/// Transcript | Summary | Action Items tab bar, and the two panes behind it.
///
/// The row itself (`RecordingRow`) owns the *jobs* — starting a generation,
/// switching to the tab it lands in, showing a failure — while this file owns
/// the *reading* of what came back. Splitting it that way keeps the row's hover
/// chrome and the insight chrome from growing into one 900-line view, and it
/// means the panes take plain values (text, items) rather than reaching into the
/// store themselves.
///
/// Nothing here holds state that must survive the row: `FlushPlate` is lazy, so
/// a row scrolled out of view is torn down. Which tab is selected therefore
/// lives in the enclosing pane (see `RecordingsList`) and arrives as a binding.

// MARK: - Tabs

/// The three views of one recording. `.transcript` always exists; the other two
/// only appear once that insight has been generated (or is being generated).
nonisolated enum InsightTab: Hashable, Sendable {
    case transcript
    case summary
    case actionItems

    var title: String {
        switch self {
        case .transcript: return "Transcript"
        case .summary: return "Summary"
        case .actionItems: return "Action Items"
        }
    }

    var symbolName: String {
        switch self {
        // Deliberately not "text.alignleft" — that belongs to the Summary tab
        // (it is `InsightKind.summary.symbolName`), and two identical glyphs
        // side by side would make the bar unreadable at 10pt.
        case .transcript: return "text.quote"
        case .summary: return InsightKind.summary.symbolName
        case .actionItems: return InsightKind.actionItems.symbolName
        }
    }

    var help: String {
        switch self {
        case .transcript: return "Show the transcript"
        case .summary: return "Show the summary"
        case .actionItems: return "Show the action items"
        }
    }

    /// The generated insight this tab shows, or `nil` for the transcript.
    var kind: InsightKind? {
        switch self {
        case .transcript: return nil
        case .summary: return .summary
        case .actionItems: return .actionItems
        }
    }

    /// The tabs a given recording actually has: the transcript always, then
    /// each insight that is stored on the entry *or* being generated right now.
    /// A job in flight earns its tab immediately, so its spinner has somewhere
    /// to live and the user can watch the thing they just asked for.
    ///
    /// `@MainActor` because it asks the generator what is running; the enum
    /// itself stays `nonisolated` like every other pure value type here.
    @MainActor
    static func visible(
        for entry: RecordingHistoryEntry,
        generator: TranscriptInsightGenerator
    ) -> [InsightTab] {
        var tabs: [InsightTab] = [.transcript]
        for kind in InsightKind.allCases
        where entry.hasInsight(kind) || generator.isRunning(entryID: entry.id, kind: kind) {
            tabs.append(kind.tab)
        }
        return tabs
    }
}

extension InsightKind {
    /// The tab this insight is read in.
    nonisolated var tab: InsightTab {
        switch self {
        case .summary: return .summary
        case .actionItems: return .actionItems
        }
    }

    /// Lowercase noun for menu commands — "Generate summary", "Regenerate
    /// action items". `displayName` is Title Case and would read as a shout
    /// mid-sentence.
    nonisolated var commandNoun: String {
        switch self {
        case .summary: return "summary"
        case .actionItems: return "action items"
        }
    }

    /// Present-tense copy shown while the job runs. Names the work, not the
    /// model: the user asked for a summary, not for a chat completion.
    nonisolated var runningLabel: String {
        switch self {
        case .summary: return "Summarizing…"
        case .actionItems: return "Finding action items…"
        }
    }
}

// MARK: - Tab bar

/// A compact capsule segmented control over one recording's views. Sized to its
/// labels rather than the row width — it is a switch between three readings of
/// the same content, not a toolbar, and a full-width bar would out-shout the
/// transcript underneath it.
struct InsightTabBar: View {
    let entry: RecordingHistoryEntry
    let tabs: [InsightTab]
    @Binding var selection: InsightTab

    @Bindable private var generator = TranscriptInsightGenerator.shared
    @Environment(\.motion) private var motion
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(tabs, id: \.self) { tab in
                InsightTabSegment(
                    tab: tab,
                    isSelected: tab == selection,
                    isRunning: isRunning(tab),
                    badge: badge(for: tab),
                    namespace: namespace
                ) {
                    selection = tab
                }
            }
        }
        // Scoped to the bar rather than wrapped around the write: `selection`
        // writes through to the pane's tab map, so a `withAnimation` there would
        // animate everything the swap causes — the pane swap and the row's whole
        // height reflow, springing every row below it. `select` is the token for
        // a selection capsule; the container's own reflow is `layout`, applied by
        // `RecordingRow.contentSection`.
        .animation(motion.select, value: selection)
        .padding(Space.s1)
        .background(Capsule(style: .continuous).fill(Palette.wellFill))
        // Hug the labels: the bar is left-aligned inside the row's leading stack.
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording views")
    }

    private func isRunning(_ tab: InsightTab) -> Bool {
        guard let kind = tab.kind else { return false }
        return generator.isRunning(entryID: entry.id, kind: kind)
    }

    /// The Action Items tab carries its count, so the user can see there are
    /// seven of them without opening the tab. Nothing else is badged.
    private func badge(for tab: InsightTab) -> Int? {
        guard tab == .actionItems else { return nil }
        let count = entry.actionItems?.items.count ?? 0
        return count > 0 ? count : nil
    }
}

/// One segment of the bar. Its own view so the hover lift is per-segment state
/// rather than a dictionary in the bar.
private struct InsightTabSegment: View {
    let tab: InsightTab
    let isSelected: Bool
    let isRunning: Bool
    let badge: Int?
    let namespace: Namespace.ID
    let action: () -> Void

    @Environment(\.motion) private var motion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s2) {
                leading
                Text(tab.title)
                    .typo(.captionMedium)
                if let badge {
                    Text("\(badge)")
                        .typo(.mono)
                }
            }
            .foregroundStyle(labelInk)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .background {
                if isSelected {
                    // ONE pill per bar: it slides between segments instead of
                    // fading out here and in over there.
                    //
                    // Filled with the accent wash, like every other selection
                    // capsule in the app (`SettingsSidebar`, `IOSGroupedList`).
                    // `Palette.plate` is what `Palette.wellFill` is composited
                    // *on*, so a plate pill on the bar's own track was a ~1.1:1
                    // difference — under the 3:1 a state indicator needs, with no
                    // Increase Contrast variant to rescue it, and indistinguishable
                    // from the hover fill below.
                    Capsule(style: .continuous)
                        .fill(Palette.accent.opacity(0.16))
                        .matchedGeometryEffect(id: "insights.tab.selection", in: namespace)
                } else if isHovering {
                    // Stacked on the track's own wellFill this composites to about
                    // 9% ink: a visible step that still sits clearly below the
                    // accent selection, so hover can never read as selected.
                    Capsule(style: .continuous)
                        .fill(Palette.wellFill)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(motion.hover) { isHovering = hovering }
        }
        .help(tab.help)
        // The badge and the spinner are the two things this segment exists to
        // carry, and both are visual-only — an `accessibilityLabel` alone would
        // replace them with a bare title, announcing a seven-item checklist
        // exactly like an empty one.
        .accessibilityLabel(badge.map { "\(tab.title), \($0) items" } ?? tab.title)
        .accessibilityValue(isRunning ? "Generating" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The spinner replaces the symbol while that tab's job runs, so a running
    /// generation is visible even from the tab the user is currently reading.
    @ViewBuilder
    private var leading: some View {
        if isRunning {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                // `scaleEffect` shrinks the drawing, not the layout slot, so
                // the spinner is boxed to about the symbol's size — otherwise
                // the whole bar jumps wider the moment a job starts.
                .frame(width: Space.s5, height: Space.s5)
        } else {
            Image(systemName: tab.symbolName)
                .font(Typo.micro)
                .frame(width: Space.s5, height: Space.s5)
        }
    }

    /// Accent is the load-bearing cue for selection, so hover cannot mimic it:
    /// a hovered unselected segment reads as plain ink under a quiet fill, never
    /// as the selected treatment.
    private var labelInk: Color {
        if isSelected { return Palette.accent }
        return isHovering ? Palette.ink : Palette.inkMuted
    }
}

// MARK: - Pane

/// The body behind the Summary or Action Items tab: a header strip (when it was
/// generated, copy, remove), a stale banner when the transcript has moved on
/// since, and the insight itself — or, when nothing has been generated yet, the
/// running state.
///
/// Content the user is reading is never blanked out for a spinner: a
/// regeneration over an existing insight keeps the old one on screen and puts
/// the spinner in the header instead.
struct InsightPane: View {
    let entry: RecordingHistoryEntry
    let kind: InsightKind
    /// Flips one action item's done state. Ignored by the summary pane.
    let onToggleActionItem: (UUID) -> Void
    /// Drops just this insight from the recording.
    let onRemove: () -> Void
    /// Re-runs the generator for this kind — the stale banner's way out.
    let onRegenerate: () -> Void

    @Bindable private var generator = TranscriptInsightGenerator.shared
    @Environment(\.increaseContrast) private var increaseContrast

    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    private var isRunning: Bool { generator.isRunning(entryID: entry.id, kind: kind) }

    private var progress: TranscriptInsightGenerator.Progress? {
        generator.progress(entryID: entry.id, kind: kind)
    }

    private var hasContent: Bool { entry.hasInsight(kind) }

    private var faintInk: Color { Palette.inkFaint(increaseContrast: increaseContrast) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if hasContent {
                header
                if entry.isStale(kind) {
                    staleBanner
                }
                content
            } else if isRunning {
                runningRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { copyResetTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.s4) {
            if isRunning {
                spinner
            }
            Text(caption)
                .typo(.caption)
                .foregroundStyle(faintInk)
            if isRunning, let progress {
                Text(Self.progressLabel(progress))
                    .typo(.mono)
                    .contentTransition(.numericText())
                    .foregroundStyle(faintInk)
            }
            Spacer(minLength: Space.s4)
            InsightIconButton(
                systemName: copied ? "checkmark" : "doc.on.doc",
                tint: copied ? Palette.signalReady : Palette.inkMuted,
                help: copyHelp,
                action: copy
            )
            InsightIconButton(
                systemName: "trash",
                tint: Palette.inkMuted,
                help: "Remove this \(kind.commandNoun)",
                action: onRemove
            )
        }
    }

    /// "Summary · 3 min. ago" / "5 action items · 2 done" — what it is and how
    /// fresh, in one tertiary line that never competes with the content.
    private var caption: String {
        switch kind {
        case .summary:
            guard let summary = entry.summary else { return kind.displayName }
            return "\(kind.displayName) · \(InsightTimestamp.relative(summary.generatedAt))"
        case .actionItems:
            guard let actionItems = entry.actionItems else { return kind.displayName }
            let count = actionItems.items.count
            let noun = count == 1 ? "1 action item" : "\(count) action items"
            guard actionItems.doneCount > 0 else { return noun }
            return "\(noun) · \(actionItems.doneCount) done"
        }
    }

    private var copyHelp: String {
        switch kind {
        case .summary: return "Copy summary"
        case .actionItems: return "Copy action items"
        }
    }

    // MARK: Banners

    /// The transcript was regenerated (or a version removed) after this insight
    /// was made, so what it describes is no longer what the row shows. Quiet,
    /// not modal — the stale text is still useful, it is just not current.
    private var staleBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            Image(systemName: "exclamationmark.triangle")
                .font(Typo.micro)
                .foregroundStyle(Palette.signalWarn)
            Text("The transcript changed after this was generated.")
                .typo(.caption)
                .foregroundStyle(Palette.signalWarn)
                .fixedSize(horizontal: false, vertical: true)
            Button("Regenerate", action: onRegenerate)
                .buttonStyle(.plain)
                .typo(.captionMedium)
                .foregroundStyle(Palette.accent)
                .disabled(isRunning)
                .help("Generate the \(kind.commandNoun) again from the current transcript")
        }
    }

    /// First-run state: nothing to read yet, so the pane *is* the progress.
    private var runningRow: some View {
        HStack(spacing: Space.s4) {
            spinner
            Text(kind.runningLabel)
                .typo(.caption)
                .foregroundStyle(faintInk)
            if let progress {
                Text(Self.progressLabel(progress))
                    .typo(.mono)
                    .contentTransition(.numericText())
                    .foregroundStyle(faintInk)
            }
        }
    }

    private var spinner: some View {
        ProgressView()
            .controlSize(.small)
            .scaleEffect(0.6)
            .frame(width: Space.s5, height: Space.s5)
    }

    /// Only chunked jobs report progress — a transcript short enough to send in
    /// one request has no parts to count, and `progress(...)` returns nil there.
    private static func progressLabel(_ progress: TranscriptInsightGenerator.Progress) -> String {
        "part \(progress.done) of \(progress.total)"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .summary:
            if let summary = entry.summary {
                SummaryTabContent(text: summary.text)
            }
        case .actionItems:
            if let actionItems = entry.actionItems {
                ActionItemsTabContent(items: actionItems.items, onToggle: onToggleActionItem)
            }
        }
    }

    // MARK: Copy

    private func copy() {
        let text: String
        switch kind {
        case .summary:
            text = entry.summary?.text ?? ""
        case .actionItems:
            text = InsightClipboard.markdownChecklist(entry.actionItems?.items ?? [])
        }
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

// MARK: - Summary content

/// The summary as designed blocks rather than raw model output: a topic label
/// becomes a heading over its points, a bulleted line a real bullet with a
/// hanging indent, everything else a paragraph. The model is asked for plain
/// text, but it still writes lists — rendering "- " as a literal dash is how a
/// pane starts looking like a terminal.
///
/// Which line is which is decided by `SummaryLayout`, over in
/// `TranscriptInsightRequest.swift` beside the prompt that asked for the shape.
/// Only the drawing is here.
struct SummaryTabContent: View {
    let text: String

    @Environment(\.motion) private var motion
    @Environment(\.increaseContrast) private var increaseContrast
    @State private var expanded = false

    /// Blocks shown before the summary clamps. The count of blocks is the clamp
    /// here — not a line limit — so there are no hidden measuring probes to pay
    /// for: a bullet list is either short enough to read at a glance or it is a
    /// document, and the block count tells the two apart exactly.
    private static let collapsedBlockLimit = 6

    var body: some View {
        let blocks = SummaryLayout.blocks(of: text)
        let shown = expanded ? blocks : Array(blocks.prefix(Self.collapsedBlockLimit))

        VStack(alignment: .leading, spacing: Space.s4) {
            ForEach(shown) { block in
                // `id` is the block's position in the parsed run, so the first
                // block of the summary is the one that needs no air above it —
                // and it is still the first one when the list is collapsed.
                blockView(block, isFirst: block.id == 0)
            }
            if blocks.count > Self.collapsedBlockLimit {
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation(motion.layout) { expanded.toggle() }
                }
                .buttonStyle(.plain)
                .typo(.captionMedium)
                .foregroundStyle(Palette.accent)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: SummaryLayout.Block, isFirst: Bool) -> some View {
        switch block.shape {
        case .paragraph:
            Text(block.text)
                .typo(.body)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet:
            // Baseline alignment is what makes the indent hang: wrapped lines
            // sit under the text, never under the dot.
            HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                Text("•")
                    .typo(.body)
                    .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                Text(block.text)
                    .typo(.body)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .heading:
            // A label above its points, not a shout: the body around it is
            // `.body` in `Palette.inkMuted`, so one step smaller and one step
            // darker is all it takes to read as a different kind of line. The
            // air above separates this group from the previous one, which the
            // very first block has nothing to separate from.
            Text(block.text)
                .typo(.captionMedium)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, isFirst ? 0 : Space.s2)
        }
    }
}

// MARK: - Action items content

/// One checkable row per action item, with owner and due date as quiet chips on
/// a second line. Checking an item writes straight through to History — this is
/// a to-do list the user keeps, not a read-only report.
struct ActionItemsTabContent: View {
    let items: [ActionItem]
    let onToggle: (UUID) -> Void

    @Environment(\.increaseContrast) private var increaseContrast

    private var faintInk: Color { Palette.inkFaint(increaseContrast: increaseContrast) }

    var body: some View {
        if items.isEmpty {
            // A real answer, not an error: plenty of conversations genuinely
            // commit nobody to anything.
            Text("No action items came out of this conversation.")
                .typo(.body)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: Space.s4) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ item: ActionItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            Button {
                onToggle(item.id)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(Typo.body)
                    .foregroundStyle(item.isDone ? Palette.accent : Palette.inkMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Mark as not done" : "Mark as done")
            .accessibilityLabel(item.text)
            .accessibilityAddTraits(item.isDone ? [.isSelected] : [])

            VStack(alignment: .leading, spacing: Space.s2) {
                Text(item.text)
                    .typo(.body)
                    .foregroundStyle(item.isDone ? faintInk : Palette.ink)
                    .strikethrough(item.isDone)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.owner != nil || item.due != nil {
                    HStack(spacing: Space.s3) {
                        if let owner = item.owner, !owner.isEmpty {
                            chip(symbol: "person", text: owner)
                        }
                        if let due = item.due, !due.isEmpty {
                            chip(symbol: "clock", text: due)
                        }
                    }
                }
            }
        }
    }

    /// Owner / due as a capsule in the well fill: metadata about the task, held
    /// visibly below it rather than crammed into the task's own sentence.
    private func chip(symbol: String, text: String) -> some View {
        HStack(spacing: Space.s1) {
            Image(systemName: symbol)
                .font(Typo.micro)
            Text(text)
                .typo(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(faintInk)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s1)
        .background(Capsule(style: .continuous).fill(Palette.wellFill))
    }
}

// MARK: - Shared pieces

/// The 22pt icon button of the insight header strip — the same size, weight and
/// copy-confirmation behaviour as `TranscriptBlockView`'s per-version controls,
/// so the two strips of chrome inside one recording read as one family.
private struct InsightIconButton: View {
    let systemName: String
    let tint: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Typo.captionMedium)
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// How fresh an insight is, in the header strip's tertiary line.
nonisolated enum InsightTimestamp {
    /// "3 min. ago", "yesterday". Abbreviated because it shares an 11pt line
    /// with the insight's name and the row's controls.
    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

/// What lands on the pasteboard when action items are copied.
nonisolated enum InsightClipboard {
    /// A markdown checklist — one line per item, done state preserved, owner
    /// and due appended when the transcript named them. Markdown because the
    /// destination is almost always a notes app or a ticket, both of which
    /// render "- [ ]" as a real checkbox.
    static func markdownChecklist(_ items: [ActionItem]) -> String {
        items.map { item in
            var line = item.isDone ? "- [x] \(item.text)" : "- [ ] \(item.text)"
            if let owner = item.owner, !owner.isEmpty {
                line += " — \(owner)"
            }
            if let due = item.due, !due.isEmpty {
                line += " (\(due))"
            }
            return line
        }
        .joined(separator: "\n")
    }
}
