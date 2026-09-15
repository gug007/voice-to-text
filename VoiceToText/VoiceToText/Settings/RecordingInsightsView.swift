import AppKit
import SwiftUI

/// Everything the AI-insight layer of a recording row draws: the
/// Transcript | Summary | Action Items | … tab bar, the panes behind it, and
/// the "Format with AI" popover that collects a custom instruction.
///
/// The row itself (`RecordingRow`) owns the *jobs* — starting a generation,
/// switching to the tab it lands in, showing a failure — while this file owns
/// the *reading* of what came back, and the form that asks for it. Splitting it
/// that way keeps the row's hover chrome and the insight chrome from growing
/// into one 900-line view, and it means the panes take plain values (text,
/// items) rather than reaching into the store themselves.
///
/// Nothing here holds state that must survive the row: `FlushPlate` is lazy, so
/// a row scrolled out of view is torn down. Which tab is selected therefore
/// lives in the enclosing pane (see `RecordingsList`) and arrives as a binding.

// MARK: - Tabs

/// The views of one recording. `.transcript` always exists; the two built-in
/// insights only appear once they have been generated (or are being generated),
/// and each custom result the user asked for adds one more.
nonisolated enum InsightTab: Hashable, Sendable {
    case transcript
    case summary
    case actionItems
    /// One custom result, identified by the stored `CustomInsight`'s id rather
    /// than by its title: the model names the result, and a re-run can rename
    /// it, so a title-keyed tab would point at nothing the moment it landed.
    case custom(UUID)

    /// The tab's label. Custom results are named by the model, so the label has
    /// to be looked up on the recording — and a job that has not landed yet has
    /// no title to look up, which is what "Working…" stands in for.
    func title(in entry: RecordingHistoryEntry) -> String {
        switch self {
        case .transcript: return "Transcript"
        case .summary: return InsightKind.summary.displayName
        case .actionItems: return InsightKind.actionItems.displayName
        case .custom(let id): return entry.customInsight(id: id)?.title ?? "Working…"
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
        case .custom(let id): return InsightKind.custom(id).symbolName
        }
    }

    func help(in entry: RecordingHistoryEntry) -> String {
        switch self {
        case .transcript: return "Show the transcript"
        case .summary: return "Show the summary"
        case .actionItems: return "Show the action items"
        case .custom: return "Show “\(title(in: entry))”"
        }
    }

    /// The generated insight this tab shows, or `nil` for the transcript.
    var kind: InsightKind? {
        switch self {
        case .transcript: return nil
        case .summary: return .summary
        case .actionItems: return .actionItems
        case .custom(let id): return .custom(id)
        }
    }

    /// True for a model-named custom result — the one label the bar cannot size
    /// itself against, because this app did not write it.
    var isCustom: Bool {
        if case .custom = self { return true }
        return false
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
        for kind in InsightKind.builtIns
        where entry.hasInsight(kind) || generator.isRunning(entryID: entry.id, kind: kind) {
            tabs.append(kind.tab)
        }
        // The jobs that have not landed anywhere yet come first, for the same
        // reason the built-ins earn a tab while they run — and in the slot the
        // result is going to take: History inserts a new custom result at the
        // front of its list, so a pending tab drawn at the *end* of the group
        // would jump past its neighbours the instant it landed, while the
        // selection capsule was still sliding towards it.
        for id in runningCustomIDs(entryID: entry.id, generator: generator)
        where entry.customInsight(id: id) == nil {
            tabs.append(.custom(id))
        }
        // Then the stored results, in the order History keeps them (newest
        // first) — the bar is read left to right, so a new result arriving on
        // the end would contradict the list it was inserted into.
        for insight in entry.customInsightList {
            tabs.append(.custom(insight.id))
        }
        return tabs
    }

    /// Ids of the custom jobs in flight for one recording, in an order the tab
    /// bar can rely on.
    ///
    /// The generator answers with a `Set` — it is asked "what is running", not
    /// "in what order" — and a set's iteration order is not stable across
    /// mutations, so two jobs started together would otherwise be free to swap
    /// places in the bar on any redraw.
    @MainActor
    static func runningCustomIDs(
        entryID: UUID,
        generator: TranscriptInsightGenerator
    ) -> [UUID] {
        generator.runningCustomIDs(entryID: entryID)
            .sorted { $0.uuidString < $1.uuidString }
    }
}

extension InsightKind {
    /// The tab this insight is read in.
    nonisolated var tab: InsightTab {
        switch self {
        case .summary: return .summary
        case .actionItems: return .actionItems
        case .custom(let id): return .custom(id)
        }
    }

    /// Lowercase noun for menu commands — "Generate summary", "Regenerate
    /// action items". `displayName` is Title Case and would read as a shout
    /// mid-sentence. A custom result has no fixed noun (the model names each
    /// one), so it borrows the generic one the menu never actually uses.
    nonisolated var commandNoun: String {
        switch self {
        case .summary: return "summary"
        case .actionItems: return "action items"
        case .custom: return "result"
        }
    }

    /// Present-tense copy shown while the job runs. Names the work, not the
    /// model: the user asked for a summary, not for a chat completion.
    nonisolated var runningLabel: String {
        switch self {
        case .summary: return "Summarizing…"
        case .actionItems: return "Finding action items…"
        case .custom: return "Formatting…"
        }
    }
}

// MARK: - Tab bar

/// A compact capsule segmented control over one recording's views. Sized to its
/// labels rather than the row width — it is a switch between readings of the
/// same content, not a toolbar, and a full-width bar would out-shout the
/// transcript underneath it.
struct InsightTabBar: View {
    let entry: RecordingHistoryEntry
    let tabs: [InsightTab]
    @Binding var selection: InsightTab

    @Bindable private var generator = TranscriptInsightGenerator.shared
    @Environment(\.motion) private var motion
    @Namespace private var namespace

    /// How wide a custom tab's label may get. Three words fit comfortably; the
    /// cap exists for the model that ignores the three-word rule, which would
    /// otherwise push Transcript and Summary off the row it is sitting in.
    private static let customLabelMaxWidth: CGFloat = 110

    /// How much of the right edge fades when there are more tabs than fit. Wide
    /// enough to read as "this continues", narrow enough to leave the label
    /// under it recognisable.
    private static let overflowFadeWidth: CGFloat = 24

    @State private var barWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    /// Whether the assembled bar is wider than the space it has.
    ///
    /// It genuinely can be. A full bar is six tabs — Transcript, Summary, Action
    /// Items and three custom results — which measures well past 600pt with
    /// typical model-written titles, against a viewport the pane caps at 608pt
    /// in the default window and around 400pt at the minimum one. Four tabs
    /// already overflow at the minimum width. So this is not a backstop: the
    /// clip is a normal state that has to be visible, or the user is left with
    /// a tab bar that silently ends mid-label and no gesture suggesting more.
    private var isOverflowing: Bool { barWidth - viewportWidth > 0.5 }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.s1) {
                ForEach(tabs, id: \.self) { tab in
                    InsightTabSegment(
                        title: tab.title(in: entry),
                        symbolName: tab.symbolName,
                        help: tab.help(in: entry),
                        maxTitleWidth: tab.isCustom ? Self.customLabelMaxWidth : nil,
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
            // Hug the labels: the track is the content, not the scroll area.
            .fixedSize()
            // macOS 15 geometry observer, as in `MinimalDropdown` — MainActor
            // friendly, where a preference-key closure is not.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        // The cue that there is more bar than window: without it the right-most
        // label is simply cut, which reads as a rendering glitch rather than as
        // something to scroll. A mouse-only user has no horizontal gesture, so
        // the scroller above is the other half of this.
        .mask(alignment: .leading) {
            if isOverflowing {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: fadeStart),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Rectangle()
            }
        }
        // A horizontal ScrollView is greedy in both axes. Pin its height to the
        // bar's own so the row does not grow a scroll gutter, and keep it
        // left-aligned inside the row's leading stack.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording views")
    }

    /// Where the trailing fade begins, as a fraction of the viewport. Derived
    /// rather than fixed so the fade stays `overflowFadeWidth` points wide
    /// whatever the window is doing to the bar.
    private var fadeStart: CGFloat {
        guard viewportWidth > Self.overflowFadeWidth else { return 0 }
        return 1 - Self.overflowFadeWidth / viewportWidth
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
///
/// Takes its label as a plain string rather than the tab: a custom result's
/// title lives on the recording, and resolving it here would mean handing every
/// segment the whole entry to read one word out of.
private struct InsightTabSegment: View {
    let title: String
    let symbolName: String
    let help: String
    /// Set only for a model-named label, which is the one this app cannot size
    /// itself against; `nil` lets the app's own titles size naturally.
    let maxTitleWidth: CGFloat?
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
                Text(title)
                    .typo(.captionMedium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxTitleWidth, alignment: .leading)
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
        .help(help)
        // The badge and the spinner are the two things this segment exists to
        // carry, and both are visual-only — an `accessibilityLabel` alone would
        // replace them with a bare title, announcing a seven-item checklist
        // exactly like an empty one.
        .accessibilityLabel(badge.map { "\(title), \($0) items" } ?? title)
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
            Image(systemName: symbolName)
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

/// The body behind the Summary, Action Items or a custom tab: a header strip
/// (when it was generated — or, for a custom result, what was asked — plus
/// copy, remove and for a custom result a re-run), a stale banner when the
/// transcript has moved on since, and the insight itself — or, when nothing has
/// been generated yet, the running state.
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
    /// Re-runs the generator for this kind — the stale banner's way out, and
    /// the custom pane's "Run again". For a custom result the row re-runs the
    /// *stored* instruction against the same id, so a re-run replaces this
    /// result rather than spending another of the three slots.
    let onRegenerate: () -> Void

    @Bindable private var generator = TranscriptInsightGenerator.shared
    @Environment(\.increaseContrast) private var increaseContrast

    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    private var isRunning: Bool { generator.isRunning(entryID: entry.id, kind: kind) }

    /// The stored custom result this pane is showing, or nil for a built-in
    /// insight (and for a custom job whose first result has not landed yet).
    private var custom: CustomInsight? {
        guard let id = kind.customID else { return nil }
        return entry.customInsight(id: id)
    }

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
            captionLabel
            if isRunning, let progress {
                Text(Self.progressLabel(progress))
                    .typo(.mono)
                    .contentTransition(.numericText())
                    .foregroundStyle(faintInk)
            }
            Spacer(minLength: Space.s4)
            // Custom results are the only insight with no menu command of their
            // own — the sparkles menu offers "Custom prompt…", not "Regenerate
            // Meeting Minutes" — so the way to run one again lives here.
            if kind.isCustom {
                InsightIconButton(
                    systemName: "arrow.clockwise",
                    tint: Palette.inkMuted,
                    help: regenerateHelp,
                    action: onRegenerate
                )
                .disabled(isRunning)
                .accessibilityLabel("Run this instruction again")
            }
            InsightIconButton(
                systemName: copied ? "checkmark" : "doc.on.doc",
                tint: copied ? Palette.signalReady : Palette.inkMuted,
                help: copyHelp,
                action: copy
            )
            .accessibilityLabel(copyHelp)
            InsightIconButton(
                systemName: "trash",
                tint: Palette.inkMuted,
                help: "Remove this \(kind.commandNoun)",
                action: onRemove
            )
            .accessibilityLabel("Remove this \(kind.commandNoun)")
        }
    }

    /// The header's tertiary line. For a custom result that line is the user's
    /// own instruction, which is the one caption that can be longer than the
    /// strip — so it clamps to a line and the whole of it stays reachable as a
    /// tooltip. The app's own captions are short by construction and get no
    /// tooltip, which would only repeat what is already on screen.
    @ViewBuilder
    private var captionLabel: some View {
        if let instruction = custom?.instruction {
            captionText.help(instruction)
        } else {
            captionText
        }
    }

    private var captionText: some View {
        Text(caption)
            .typo(.caption)
            .foregroundStyle(faintInk)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// "Summary · 3 min. ago" / "5 action items · 2 done" — what it is and how
    /// fresh, in one tertiary line that never competes with the content. A
    /// custom result says what was *asked* instead: its title is already on the
    /// tab, and the instruction is the thing the user cannot otherwise see.
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
        case .custom:
            guard let custom else { return kind.displayName }
            return custom.instruction
        }
    }

    private var copyHelp: String {
        switch kind {
        case .summary: return "Copy summary"
        case .actionItems: return "Copy action items"
        case .custom: return "Copy this result"
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
            Button(kind.isCustom ? "Run again" : "Regenerate", action: onRegenerate)
                .buttonStyle(.plain)
                .typo(.captionMedium)
                .foregroundStyle(Palette.accent)
                .disabled(isRunning)
                .help(regenerateHelp)
        }
    }

    /// One sentence for both ways back to a fresh result: the stale banner's
    /// button and, on a custom result, the header's re-run. A custom result
    /// re-runs the instruction the user already typed, so it says so rather
    /// than talking about "regenerating" something the model named.
    private var regenerateHelp: String {
        kind.isCustom
            ? "Run this instruction again on the current transcript"
            : "Generate the \(kind.commandNoun) again from the current transcript"
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
        case .custom:
            // Same renderer as the summary, because the custom prompt asks for
            // exactly the summary's plain-text shape: paragraphs, "- " bullets
            // and a heading as its own line ending in a colon.
            if let custom {
                SummaryTabContent(text: custom.text)
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
        case .custom:
            text = custom?.text ?? ""
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

// MARK: - Custom prompt

/// The "Format with AI" form: one instruction, typed by the user, that the model
/// applies to this recording's transcript. The result comes back as its own tab
/// beside Summary and Action Items.
///
/// This view only *collects* the instruction — it hands the trimmed text to the
/// row and closes. The row starts the job, for the lifetime reason its other
/// generations are started from a button action rather than a `.task`.
///
/// Presented as a popover from the row's sparkles button, so it is glass surface
/// #4 of the inventory in `GlassSurface.swift` and filled with a `Rectangle`:
/// the popover already owns the corner radius.
struct CustomPromptPopover: View {
    /// How many of the recording's result slots are already spoken for —
    /// stored results *plus* any job still generating one — and how many it has.
    /// Passed in rather than read off the entry so the form has no opinion about
    /// where the cap lives, and counted with the jobs in flight because a slot
    /// something is on its way to filling is not free: without that the user can
    /// type a fourth instruction while the third is still running, and pay for a
    /// document the store will refuse.
    let usedCount: Int
    let maxCount: Int
    /// The last thing that went wrong with a custom job on this recording, if
    /// anything has. A refused *new* result has no tab to be shown on — it was
    /// never stored — so the form it was typed in is where the user comes back
    /// to and where the message has to be waiting.
    let failureMessage: String?
    /// Clears that message, here and on the recording.
    let onDismissFailure: () -> Void
    /// Called with the trimmed instruction when the user commits.
    let onSubmit: (String) -> Void

    @Bindable private var promptStore = InsightPromptStore.shared
    @Environment(\.increaseContrast) private var increaseContrast

    @State private var instruction = ""
    @FocusState private var isFieldFocused: Bool

    /// The popover's width. Wide enough for a sentence of instruction at three
    /// lines, narrow enough to still read as a popover rather than a sheet.
    private static let width: CGFloat = 300

    private var trimmed: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFull: Bool { usedCount >= maxCount }

    private var faintInk: Color { Palette.inkFaint(increaseContrast: increaseContrast) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Format with AI")
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                Text("Applies your instruction to this recording's transcript and keeps the result in its own tab.")
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            field

            if let failureMessage {
                failureNote(failureMessage)
            }

            if isFull {
                capNote
            }

            HStack(spacing: Space.s4) {
                Spacer(minLength: Space.s4)
                CapsuleActionButton(
                    title: "Format",
                    systemImage: "wand.and.sparkles",
                    isDisabled: trimmed.isEmpty || isFull,
                    action: submit
                )
                // ⌘↩ rather than ↩: the field is multi-line, so Return belongs to
                // the text being typed.
                .keyboardShortcut(.return, modifiers: .command)
                .help("Apply this instruction to the transcript (⌘↩)")
            }

            if !promptStore.prompts.isEmpty {
                recentSection
            }
        }
        .padding(Space.s6)
        .frame(width: Self.width)
        .glassSurface(in: Rectangle())
        // Focus is taken after the first render rather than in `onAppear`: a
        // popover is not key yet while its content is first being laid out, and
        // focus asked for then is dropped on the floor.
        .task { isFieldFocused = true }
    }

    // MARK: Field

    private var field: some View {
        TextField(
            "Instruction",
            text: $instruction,
            prompt: Text("Rewrite this as meeting minutes…").foregroundStyle(faintInk),
            axis: .vertical
        )
        .labelsHidden()
        .textFieldStyle(.plain)
        .font(Typo.body)
        .foregroundStyle(Palette.ink)
        .lineLimit(3...6)
        .focused($isFieldFocused)
        .padding(Space.s5)
        .background {
            // The app's own well rather than a stock bordered field, so the form
            // reads as part of the row it opened from.
            ConcentricRectangle(inset: Space.s3) { shape in
                shape
                    .fill(Palette.wellFill)
                    .overlay(shape.strokeBorder(Palette.hairline))
            }
        }
        // No `.onSubmit`: on macOS a vertical-axis field hands a plain Return to
        // the submit action, which would send a half-typed instruction the moment
        // the user reached for a second line — and spend a request and one of the
        // three slots doing it. ⌘↩ on the Format button is the one commit path.
        .accessibilityLabel("Formatting instruction")
        .help("Tell the AI what to do with this transcript")
    }

    /// What went wrong last time, in the same warning language as the row's own
    /// failure notes — and dismissible here, because this is often the only
    /// place a refused new result was ever mentioned.
    private func failureNote(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(message)
                .typo(.caption)
                .foregroundStyle(Palette.signalWarn)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", action: onDismissFailure)
                .buttonStyle(.plain)
                .typo(.captionMedium)
                .foregroundStyle(Palette.accent)
                .help("Hide this message")
        }
    }

    /// Shown only at the cap. Warning-coloured because it is the reason the
    /// button below it is dead, not a hint.
    private var capNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(Typo.micro)
                .foregroundStyle(Palette.signalWarn)
            Text("This recording already has \(maxCount) formatted results. Remove one to add another.")
                .typo(.caption)
                .foregroundStyle(Palette.signalWarn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Recent

    /// Instructions the user has typed before, newest first. A convenience, not
    /// the main event: quiet type, no fills, and it is absent entirely until
    /// there is something to remember.
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Recent")
                .typo(.micro)
                .textCase(.uppercase)
                .foregroundStyle(faintInk)
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(promptStore.prompts) { prompt in
                    RecentPromptRow(
                        instruction: prompt.instruction,
                        onUse: {
                            // Fills the field rather than running: a remembered
                            // instruction is usually the *start* of the next one
                            // ("…and in Russian"), and a one-tap run from a list
                            // of similar-looking sentences is a mis-click that
                            // costs a request.
                            instruction = prompt.instruction
                            isFieldFocused = true
                        },
                        onForget: { promptStore.forget(id: prompt.id) }
                    )
                }
            }
        }
    }

    private func submit() {
        let text = trimmed
        guard !text.isEmpty, !isFull else { return }
        onSubmit(text)
    }
}

/// One remembered instruction: tap the text to load it into the field, the
/// xmark to forget it. Its own view so the hover wash is per-row state.
private struct RecentPromptRow: View {
    let instruction: String
    let onUse: () -> Void
    let onForget: () -> Void

    @Environment(\.motion) private var motion
    @Environment(\.increaseContrast) private var increaseContrast
    @State private var isHovering = false
    @FocusState private var isForgetFocused: Bool

    var body: some View {
        HStack(spacing: Space.s2) {
            Button(action: onUse) {
                Text(instruction)
                    .typo(.caption)
                    .foregroundStyle(isHovering ? Palette.ink : Palette.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Use “\(instruction)”")
            .accessibilityLabel("Use instruction: \(instruction)")

            Button(action: onForget) {
                Image(systemName: "xmark")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                    // The 22pt hit area of the insight header's icon buttons, so
                    // a 10pt glyph is still a real target.
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isForgetFocused)
            // Revealed by hover *or* by focus. Keeping it in the tree made it
            // reachable by keyboard, but at opacity 0 that meant Full Keyboard
            // Access drawing a focus ring around blank space, and Space quietly
            // forgetting an instruction the user was never shown a control for.
            // Never hidden from VoiceOver either, for the same reason.
            .opacity(isHovering || isForgetFocused ? 1 : 0)
            .help("Forget this instruction")
            .accessibilityLabel("Forget instruction: \(instruction)")
            .accessibilityHidden(false)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s1)
        .background(
            RoundedRectangle(cornerRadius: Radius.minimum, style: .continuous)
                .fill(isHovering ? Palette.wellFill : Color.clear)
        )
        .onHover { hovering in
            withAnimation(motion.hover) { isHovering = hovering }
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
