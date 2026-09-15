import AppKit
import SwiftUI

/// One command in the row's sparkles menu. The two built-in insights are named
/// by the kind they generate; "Custom prompt…" opens a form instead of starting
/// anything, which is exactly why it cannot be an `InsightKind` — there is no
/// id to name until the user has typed an instruction and the model has answered.
///
/// `nonisolated` because it is a `DropdownItem`'s value: its `Hashable`
/// witnesses are called by the dropdown's `ForEach` and comparisons, which a
/// MainActor-isolated type could not satisfy under Swift 6.
private nonisolated enum InsightMenuCommand: Hashable {
    case generate(InsightKind)
    case customPrompt
}

/// A single saved-recording row: leading play tile, timestamp + metadata, copy
/// and delete controls, and the transcript(s) below. After a regeneration a
/// recording can hold more than one transcript; each version is then shown in
/// its own labeled block with per-version copy and remove. Chrome-less — the
/// enclosing `RecordingsList` draws the grouped card and the hairline separators
/// between rows. Shared by the History pane (all recordings) and the
/// Conversations pane (conversations only).
///
/// Once a recording has an AI summary, a checklist or a custom result — or one
/// is being generated — the content area grows a tab bar and the transcript
/// becomes one of several readings of the same recording. All of that chrome
/// lives in `RecordingInsightsView.swift`; this row owns the *jobs*: starting
/// one from the sparkles menu, the custom-prompt popover or the inline strip,
/// following it to its tab, and showing what went wrong when it fails.
struct RecordingRow: View {
    let entry: RecordingHistoryEntry
    let isPlaying: Bool
    /// Hidden in the Conversations list, where every row is the same type.
    var showsTypeBadge: Bool = true
    /// The live History search query, so matched substrings can be marked in
    /// the transcript. Empty everywhere else.
    var highlight: String = ""
    /// Which of Transcript / Summary / Action Items this row is showing. Owned
    /// by the pane, not by this view — see `RecordingsList` for why a row that
    /// scrolls out of view must not take its selection with it.
    @Binding var selectedTab: InsightTab
    let onPlay: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    /// Removes one transcript version (by variant id) from this recording.
    let onRemoveTranscript: (UUID) -> Void
    /// Persists the canonical-label → name mapping for this recording.
    let onRenameSpeakers: ([String: String]) -> Void
    /// Flips one action item's done state on this recording.
    let onToggleActionItem: (UUID) -> Void
    /// Drops one generated insight (summary or checklist) from this recording.
    let onRemoveInsight: (InsightKind) -> Void

    @Environment(\.motion) private var motion
    @Environment(\.increaseContrast) private var increaseContrast

    @Bindable private var regenerator = TranscriptRegenerator.shared
    @Bindable private var insights = TranscriptInsightGenerator.shared
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var showRegenerateMenu = false
    @State private var showInsightMenu = false
    /// The "Format with AI" popover, anchored to the same sparkles button as the
    /// menu that offers it.
    @State private var showCustomPrompt = false
    /// True only during the menu-to-form handoff, where neither popover flag is
    /// set and the pointer is off the row. Without it the sparkles button — the
    /// anchor the form is about to be presented from — unmounts for those two
    /// frames and the popover is asked to present on a brand-new view.
    @State private var isOpeningCustomPrompt = false
    @State private var showRenameSpeakers = false
    /// Draft names shown in the rename popover, seeded from the entry on open and
    /// committed to the store when the popover closes.
    @State private var speakerNameDrafts: [String: String] = [:]
    /// Row action icons stay hidden until the pointer is over the row — the list
    /// reads calm at rest and reveals its controls on demand.
    @State private var isHovering = false

    private var isRegenerating: Bool { regenerator.activeID == entry.id }

    /// Tertiary ink for this row's metadata, collapsed into `inkMuted` under
    /// Increase Contrast. The row is the surface History's search highlight
    /// lands on, so its whole ramp has to be the same one the highlight uses.
    private var faintInk: Color {
        Palette.inkFaint(increaseContrast: increaseContrast)
    }

    /// Canonical speaker labels present in the stored transcript. The rename
    /// control only appears when this is non-empty (i.e. a diarized recording).
    private var speakerLabels: [String] { SpeakerRelabeler.speakerLabels(in: entry.transcript) }

    /// Applies the entry's speaker-name mapping to any transcript variant for
    /// display and copy — the stored string keeps its canonical "Speaker N" labels.
    private func displayText(_ text: String) -> String {
        SpeakerRelabeler.apply(names: entry.speakerNames ?? [:], to: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(alignment: .center, spacing: Space.s5) {
                PlayTile(isPlaying: isPlaying, action: onPlay)

                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(RecordingDateFormat.rowLabel(entry.createdAt))
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: Space.s3) {
                        if showsTypeBadge {
                            RecordingTypeBadge(source: entry.source)
                            Text("·")
                                .typo(.caption)
                                .foregroundStyle(faintInk)
                        }
                        Text(metaLine)
                            .typo(.mono)
                            .foregroundStyle(faintInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: Space.s5)

                actionButtons
            }

            contentSection

            insightFailures

            if let failure = regenerator.failure, failure.id == entry.id {
                HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                    Text(failure.message)
                        .typo(.caption)
                        .foregroundStyle(Palette.signalWarn)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Dismiss") { regenerator.dismissFailure() }
                        .buttonStyle(.plain)
                        .typo(.captionMedium)
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(motion.hover, value: isHovering)
        .onDisappear { copyResetTask?.cancel() }
    }

    /// Favorite / regenerate / copy / delete. Quiet by default: only the star
    /// shows when a recording is favorited; the full set appears on hover (and
    /// the regenerate spinner stays put while a regeneration is in flight).
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: Space.s3) {
            if entry.isFavorited || isHovering {
                iconButton(
                    systemName: entry.isFavorited ? "star.fill" : "star",
                    help: entry.isFavorited ? "Remove from Favorites" : "Add to Favorites",
                    tint: entry.isFavorited ? Palette.favorite : Palette.inkMuted,
                    action: onToggleFavorite
                )
            }
            // Popover-open states keep the anchor buttons mounted after the
            // pointer leaves the row — an anchor that unmounts (hover ends when
            // the cursor enters the popover) tears its popover down with it.
            if isHovering || isRegenerating || showRenameSpeakers || showRegenerateMenu
                || showInsightMenu || showCustomPrompt || isOpeningCustomPrompt {
                if !speakerLabels.isEmpty {
                    renameSpeakersControl
                }
                regenerateControl
                insightControl
                iconButton(
                    systemName: copied ? "checkmark" : "doc.on.doc",
                    help: "Copy transcript",
                    tint: copied ? Palette.signalReady : Palette.inkMuted,
                    action: copyActiveTranscript
                )
                iconButton(
                    systemName: "trash",
                    help: "Delete recording",
                    tint: Palette.inkMuted,
                    action: onDelete
                )
            }
        }
    }

    // MARK: - Content

    /// The row's content area. With no insights this is exactly the transcript
    /// the row has always shown, so nothing regresses for a plain recording.
    /// Once a summary or checklist exists — or one is in flight — a tab bar
    /// appears above it and the transcript becomes the first of three tabs.
    @ViewBuilder
    private var contentSection: some View {
        let tabs = InsightTab.visible(for: entry, generator: insights)
        VStack(alignment: .leading, spacing: Space.s5) {
            if tabs.count > 1 {
                InsightTabBar(entry: entry, tabs: tabs, selection: tabBinding(in: tabs))
            }
            switch shownTab(in: tabs) {
            case .transcript:
                transcriptSection
            case .summary:
                insightPane(.summary)
            case .actionItems:
                insightPane(.actionItems)
            case .custom(let id):
                insightPane(.custom(id))
            }
            generateStrip
        }
        // The pane swap and the row-height change it causes are a list mutation,
        // not a selection: `layout` is smooth, where the tab bar's own `select`
        // carries a bounce that would spring every row below this one. The bar
        // applies `select` inside its own subtree, so the capsule still springs.
        .animation(motion.layout, value: shownTab(in: tabs))
    }

    /// `.id(kind)` because two custom results share this branch of
    /// `contentSection`'s switch: without it SwiftUI keeps one pane across the
    /// swap from one custom tab to another, and with it the pane's own state —
    /// the copy confirmation and the task that clears it — so copying one result
    /// and then switching tabs shows a checkmark on a result nothing was copied
    /// from. The built-in tabs get this for free from the switch's structure.
    private func insightPane(_ kind: InsightKind) -> some View {
        InsightPane(
            entry: entry,
            kind: kind,
            onToggleActionItem: onToggleActionItem,
            onRemove: { onRemoveInsight(kind) },
            onRegenerate: { generate(kind) }
        )
        .id(kind)
    }

    /// The tab actually drawn. The pane remembers one choice per recording id,
    /// and that choice can outlive what it points at — the user removes the
    /// summary while reading it — so a tab that is no longer on offer falls back
    /// to the transcript instead of rendering an empty pane.
    private func shownTab(in tabs: [InsightTab]) -> InsightTab {
        tabs.contains(selectedTab) ? selectedTab : .transcript
    }

    private func tabBinding(in tabs: [InsightTab]) -> Binding<InsightTab> {
        Binding(
            get: { shownTab(in: tabs) },
            set: { selectedTab = $0 }
        )
    }

    /// The one-tap way in for a conversation with nothing generated yet.
    ///
    /// Conversations only. A five-second dictation has nothing to summarize and
    /// commits nobody to anything, so on a History full of dictations this strip
    /// would be pure noise under every row — and the sparkles menu is still
    /// there for the rare dictation that is worth summarizing.
    @ViewBuilder
    private var generateStrip: some View {
        if entry.source == .meeting,
           !entry.hasInsights,
           entry.customInsightList.isEmpty,
           !hasRunningInsight {
            HStack(spacing: Space.s4) {
                insightChip(title: "Summary", symbolName: "sparkles",
                            help: "Generate \(InsightKind.summary.commandNoun) from this conversation") {
                    generate(.summary)
                }
                insightChip(title: "Action items", symbolName: "checklist",
                            help: "Generate \(InsightKind.actionItems.commandNoun) from this conversation") {
                    generate(.actionItems)
                }
                // The third way in: the user's own instruction, opening the same
                // popover the sparkles menu opens. The glyph is spelled out like
                // its two neighbours, and is the one `InsightKind.custom` wears.
                insightChip(title: "Custom", symbolName: "wand.and.sparkles",
                            help: "Format this transcript with your own instruction") {
                    showCustomPrompt = true
                }
            }
        }
    }

    /// True while any job for this recording is in flight — the built-ins, or a
    /// custom result the user asked for.
    private var hasRunningInsight: Bool {
        InsightKind.builtIns.contains { insights.isRunning(entryID: entry.id, kind: $0) }
            || !InsightTab.runningCustomIDs(entryID: entry.id, generator: insights).isEmpty
    }

    private func insightChip(
        title: String,
        symbolName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                Image(systemName: symbolName)
                    .font(Typo.micro)
                Text(title)
                    .typo(.captionMedium)
            }
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .background(Capsule(style: .continuous).fill(Palette.wellFill))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// Starts a generation and, on success, brings its tab forward — the user
    /// asked for the thing, so show them the thing. A failure leaves the current
    /// tab alone and surfaces in `insightFailures`.
    ///
    /// The `Task` is started from the button action rather than from a `.task`
    /// modifier on the row on purpose: `FlushPlate` is lazy, so scrolling this
    /// row out of view tears it down, and a `.task` would be cancelled with it —
    /// killing a paid-for request mid-flight because the user scrolled. A Task
    /// created here is not tied to the view's lifetime.
    ///
    /// A custom tab's "Run again" comes through here unchanged: the generator
    /// replays the instruction stored with that result, in place, so a re-run
    /// keeps its tab and does not spend another of the three slots.
    private func generate(_ kind: InsightKind) {
        Task {
            if await insights.generate(entry: entry, kind: kind) {
                selectedTab = kind.tab
            }
        }
    }

    /// Runs a newly typed instruction over this recording's transcript — the one
    /// path `generate(_:)` cannot serve, because there is no kind to name with
    /// until the result exists.
    ///
    /// On success the row selects the tab it landed in, using the id the
    /// generator hands back. Not "whichever result is newest in History": that
    /// is only the right answer by accident today, and it is already the wrong
    /// one for a recording sitting in its undo window, whose results are written
    /// into the pending batch rather than into `entries`.
    ///
    /// The instruction itself is not remembered here: the generator does that,
    /// as soon as the request is actually spent.
    private func runCustom(instruction: String) {
        Task {
            guard let id = await insights.generateCustom(
                entry: entry,
                instruction: instruction,
                replacing: nil
            ) else { return }
            selectedTab = .custom(id)
        }
    }

    /// One row per failing job, in the same language as the regenerate failure
    /// underneath it: what went wrong, and the way out of it.
    @ViewBuilder
    private var insightFailures: some View {
        ForEach(failedKinds, id: \.self) { kind in
            if let message = insights.failure(entryID: entry.id, kind: kind) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                    Text(message)
                        .typo(.caption)
                        .foregroundStyle(Palette.signalWarn)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Dismiss") { dismissFailure(kind) }
                        .buttonStyle(.plain)
                        .typo(.captionMedium)
                        .foregroundStyle(Palette.accent)
                        .help("Hide this message")
                    // The one failure the user cannot fix from this row is a
                    // missing API key, so that one gets a door to the pane that
                    // fixes it. Asked of the generator rather than matched
                    // against the message text, which is copy, not an API.
                    if !insights.hasAPIKey {
                        Button("Open Cloud") { SettingsRouter.shared.pendingSection = .cloud }
                            .buttonStyle(.plain)
                            .typo(.captionMedium)
                            .foregroundStyle(Palette.accent)
                            .help("Open Cloud settings to add an OpenAI API key")
                    }
                }
            }
        }
    }

    /// Which jobs this row currently has a failure for, in a stable order: the
    /// built-ins first, then the custom results in tab order, then whatever is
    /// left.
    ///
    /// That last group is the point of asking the generator instead of walking
    /// the recording: a *new* custom result that was refused — the cap, a
    /// missing key, a request that failed — is not stored anywhere and is no
    /// longer running, so the one failure the user most needs to read would be
    /// the only one with no row to appear in.
    private var failedKinds: [InsightKind] {
        var ordered = InsightKind.builtIns.filter {
            insights.failure(entryID: entry.id, kind: $0) != nil
        }
        let customFailures = insights.customFailures(entryID: entry.id)
        guard !customFailures.isEmpty else { return ordered }

        let storedIDs = entry.customInsightList.map(\.id)
        ordered += storedIDs
            .filter { customFailures[$0] != nil }
            .map(InsightKind.custom)
        // Sorted only so the rows cannot reshuffle between redraws: a
        // dictionary's key order is not stable, and there is no meaningful
        // order to give ids the recording has never seen.
        ordered += customFailures.keys
            .filter { !storedIDs.contains($0) }
            .sorted { $0.uuidString < $1.uuidString }
            .map(InsightKind.custom)
        return ordered
    }

    /// Hides one failure message.
    ///
    /// A custom failure is parked twice — once on its job, once on the
    /// recording, where the instruction field reads it — so dismissing it here
    /// has to clear both, or the same sentence greets the user the next time
    /// they open the form. Clearing the recording's copy clears every custom
    /// job's message with it, which is right: they are the same note, and the
    /// user has just said they have read it.
    private func dismissFailure(_ kind: InsightKind) {
        insights.dismissFailure(entryID: entry.id, kind: kind)
        if kind.isCustom {
            insights.dismissCustomFailure(entryID: entry.id)
        }
    }

    /// One plain transcript, or — when the recording has alternate versions — a
    /// labeled, removable block per version (newest/active first).
    @ViewBuilder
    private var transcriptSection: some View {
        if entry.hasAlternateTranscripts {
            VStack(alignment: .leading, spacing: Space.s5) {
                ForEach(entry.transcriptVariants) { variant in
                    TranscriptBlockView(
                        text: displayText(variant.text),
                        highlight: highlight,
                        header: TranscriptBlockView.Header(
                            label: modelLabel(for: variant),
                            isActive: variant.id == entry.id,
                            onRemove: { onRemoveTranscript(variant.id) }
                        )
                    )
                }
            }
        } else {
            TranscriptBlockView(
                text: displayText(entry.transcript),
                highlight: highlight,
                header: nil
            )
        }
    }

    private func modelLabel(for variant: TranscriptVariant) -> String {
        variant.modelName ?? variant.modelId ?? "Transcript"
    }

    private var metaLine: String {
        var parts = [entry.durationSeconds.formattedClock]
        if let model = entry.modelName ?? entry.modelId, !model.isEmpty {
            parts.append(model)
        }
        return parts.joined(separator: " · ")
    }

    private func copyActiveTranscript() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(displayText(entry.transcript), forType: .string)
        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    /// Hover control that opens the "Name speakers" popover for a diarized
    /// recording. Names are drafted locally and committed to the store when the
    /// popover content disappears, so typing never persists mid-edit. The commit
    /// lives on the popover *content* (not an `onChange` on this button): closing
    /// the popover can unmount this hover-gated button in the same transaction,
    /// and a modifier on a view being removed never fires.
    private var renameSpeakersControl: some View {
        Button {
            speakerNameDrafts = entry.speakerNames ?? [:]
            showRenameSpeakers.toggle()
        } label: {
            Image(systemName: "person.crop.circle")
                .font(Typo.body)
                .foregroundStyle(Palette.inkMuted)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Name speakers")
        .popover(isPresented: $showRenameSpeakers, arrowEdge: .bottom) {
            speakerNamePopover
                .onDisappear { onRenameSpeakers(speakerNameDrafts) }
        }
    }

    /// One labeled text field per canonical speaker. Clearing a field reverts that
    /// speaker to its "Speaker N" label; giving two the same name merges them.
    ///
    /// Glass surface #4 of the inventory in `GlassSurface.swift` — the last of
    /// the three popovers. Filled with a `Rectangle` for the same reason as
    /// `DropdownPopup`: the popover already owns the corner radius.
    private var speakerNamePopover: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Text("Name speakers")
                .typo(.headline)
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: Space.s5) {
                ForEach(speakerLabels, id: \.self) { label in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(label)
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                        TextField(label, text: speakerNameBinding(for: label))
                            .textFieldStyle(.roundedBorder)
                            .typo(.body)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { showRenameSpeakers = false }
                    .buttonStyle(.plain)
                    .typo(.captionMedium)
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(Space.s6)
        .frame(width: 220)
        .glassSurface(in: Rectangle())
    }

    private func speakerNameBinding(for label: String) -> Binding<String> {
        Binding(
            get: { speakerNameDrafts[label] ?? "" },
            set: { speakerNameDrafts[label] = $0 }
        )
    }

    /// Either a spinner+chunk count while this row is regenerating, or a model
    /// picker menu ("Regenerate with …") that re-transcribes the stored audio.
    @ViewBuilder
    private var regenerateControl: some View {
        if isRegenerating {
            HStack(spacing: Space.s3) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                if regenerator.totalChunks > 1 {
                    Text("\(regenerator.transcribedChunks)/\(regenerator.totalChunks)")
                        .typo(.mono)
                        .contentTransition(.numericText())
                        .foregroundStyle(faintInk)
                }
            }
            .frame(minWidth: 24, minHeight: 24)
            .help("Regenerating transcript…")
        } else {
            Button {
                showRegenerateMenu.toggle()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(Typo.body)
                    .foregroundStyle(Palette.inkMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(regenerator.isRunning)
            .help("Regenerate transcript with another model")
            .popover(isPresented: $showRegenerateMenu, arrowEdge: .bottom) {
                DropdownPopup(
                    sections: regenerateModelSections,
                    selected: entry.modelId,
                    width: 260
                ) { modelId in
                    showRegenerateMenu = false
                    Task { await regenerator.regenerate(entry: entry, modelId: modelId) }
                }
            }
        }
    }

    /// Every catalog model, grouped "On this Mac" / by cloud provider, with the
    /// entry's current model checkmarked — the "Regenerate with" list restyled to
    /// the shared dropdown language.
    private var regenerateModelSections: [DropdownSection<String>] {
        var sections: [DropdownSection<String>] = []
        let all = ModelCatalog.all
        let local = all.filter { !$0.isCloud }
        if !local.isEmpty {
            sections.append(DropdownSection(
                header: "On this Mac",
                items: local.map { DropdownItem(value: $0.id, title: $0.sectionedDisplayName) }
            ))
        }
        for provider in [CloudProvider.openAI, .elevenLabs] {
            let group = all.filter { $0.backend.cloudProvider == provider }
            guard !group.isEmpty else { continue }
            sections.append(DropdownSection(
                header: provider.displayName,
                items: group.map { DropdownItem(value: $0.id, title: $0.sectionedDisplayName) }
            ))
        }
        return sections
    }

    /// Hover control opening the Generate / Regenerate menu, and — from that
    /// menu or from the inline "Custom" chip — the custom-prompt form. A
    /// `.popover` over `DropdownPopup` rather than a `Menu`, for the same reason
    /// the regenerate picker is one: the stock NSMenu can't be restyled to this
    /// chrome, and the two menus on a row must not look like they come from
    /// different apps.
    private var insightControl: some View {
        Button {
            showInsightMenu.toggle()
        } label: {
            Image(systemName: "sparkles")
                .font(Typo.body)
                .foregroundStyle(Palette.inkMuted)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Summarize, list action items, or format with your own instruction")
        .popover(isPresented: $showInsightMenu, arrowEdge: .bottom) {
            DropdownPopup(
                sections: insightMenuSections,
                selected: nil,
                width: 240
            ) { command in
                switch command {
                case .generate(let kind):
                    showInsightMenu = false
                    generate(kind)
                case .customPrompt:
                    openCustomPrompt()
                }
            }
        }
        // A second popover on the same anchor rather than a second anchor: the
        // form belongs to the sparkles button, which is where the menu that
        // offers it lives, and where the inline "Custom" chip points too.
        .popover(isPresented: $showCustomPrompt, arrowEdge: .bottom) {
            CustomPromptPopover(
                usedCount: insights.usedCustomSlots(for: entry),
                maxCount: RecordingHistoryEntry.maxCustomInsights,
                failureMessage: insights.customFailure(entryID: entry.id),
                onDismissFailure: { insights.dismissCustomFailure(entryID: entry.id) }
            ) { instruction in
                showCustomPrompt = false
                runCustom(instruction: instruction)
            }
        }
    }

    /// Hands the anchor over from the menu to the form.
    ///
    /// A popover presented in the same turn as another is dismissed never
    /// appears — AppKit is still tearing the first one down on the anchor view —
    /// so the form waits out the menu's dismissal.
    ///
    /// `isOpeningCustomPrompt` is what keeps the anchor alive across that wait.
    /// During it the pointer is inside the menu's own window (so the row is not
    /// hovered), the menu flag has just been cleared and the form's is not set
    /// yet — every term of the mount condition in `actionButtons` is false at
    /// once, and the sparkles button the form is anchored to would be destroyed
    /// and rebuilt a frame later. `showCustomPrompt` holds the condition from the
    /// moment it is set, so the handoff flag can be dropped immediately after,
    /// including when the sleep is cancelled.
    private func openCustomPrompt() {
        isOpeningCustomPrompt = true
        showInsightMenu = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            showCustomPrompt = true
            isOpeningCustomPrompt = false
        }
    }

    /// "Generate summary" until one exists, "Regenerate summary" after — one
    /// command, named for what it will actually do to this recording. Nothing is
    /// checkmarked: these are actions, not a selection.
    ///
    /// "Custom prompt…" is always offered, cap or no cap. `DropdownItem` has no
    /// disabled state to give it (the dropdown is a shared control, and growing
    /// one for a single call site would be a change to every menu in the app),
    /// so the cap is said twice instead: as this row's detail line, and — in the
    /// only place that can also stop the request — inside the form itself, where
    /// the message sits next to a dead Format button.
    private var insightMenuSections: [DropdownSection<InsightMenuCommand>] {
        var items = InsightKind.builtIns.map { kind in
            DropdownItem<InsightMenuCommand>(
                value: .generate(kind),
                title: entry.hasInsight(kind)
                    ? "Regenerate \(kind.commandNoun)"
                    : "Generate \(kind.commandNoun)"
            )
        }
        items.append(DropdownItem(
            value: .customPrompt,
            title: "Custom prompt…",
            detail: isCustomInsightFull
                ? "Remove one of the \(RecordingHistoryEntry.maxCustomInsights) results first"
                : "Format this transcript your way"
        ))
        return [DropdownSection(items: items)]
    }

    /// True when the recording has as many custom results as it may — counting
    /// the ones still being generated, so the menu's detail line agrees with the
    /// form's dead Format button rather than inviting a request that would be
    /// refused after it had been paid for.
    private var isCustomInsightFull: Bool {
        insights.usedCustomSlots(for: entry) >= RecordingHistoryEntry.maxCustomInsights
    }

    private func iconButton(
        systemName: String,
        help: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Typo.body)
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Renders one transcript: a selectable, expandable body that clamps to a few
/// lines with "Show more". With a `header` (used when a recording has more than
/// one version) it draws a labeled, lightly-tinted card with per-version copy
/// and remove; without one it's the bare text, as a single-transcript row shows.
struct TranscriptBlockView: View {
    let text: String
    /// History's live search query. Non-empty means the matched substrings are
    /// washed in `accent` @ 0.22 with `ink` on top — an `AttributedString` on
    /// the same `Text`, so selection, the line clamp and "Show more" all keep
    /// working exactly as they do unsearched.
    var highlight: String = ""
    let header: Header?

    /// Per-version chrome shown when comparing multiple transcripts.
    struct Header {
        let label: String
        let isActive: Bool
        let onRemove: () -> Void
    }

    @State private var overflowHeight: CGFloat = 0
    @State private var clampedHeight: CGFloat = 0
    @State private var expanded = false
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    @Environment(\.motion) private var motion

    /// Lines shown before the transcript is clamped and a "Show more" appears.
    /// Kept short so a collapsed row scans as a preview, not a wall of text.
    private static let collapsedLineLimit = 3

    /// One source of truth for the transcript type, shared by the visible body
    /// and the hidden measuring probes so truncation is measured against exactly
    /// what's drawn — including the step's line-height, which the probes have to
    /// carry or they measure a shorter block than the row draws.
    private static let transcriptStyle: Typo.Style = .body

    /// Truncated when one extra line would make the transcript taller — i.e. it
    /// overflows the collapsed clamp. Derived from stable, expand-independent
    /// measurements (below), so toggling "Show more" never re-measures and
    /// flickers the layout.
    private var isTruncated: Bool { overflowHeight > clampedHeight + 1 }

    var body: some View {
        content
            .onDisappear { copyResetTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        if let header {
            // A version block is a well inside the row's plate, so its radius is
            // derived from the enclosing plate rather than typed.
            ConcentricRectangle(inset: Space.s3) { shape in
                VStack(alignment: .leading, spacing: Space.s4) {
                    headerRow(header)
                    transcriptBody
                }
                .padding(Space.s5)
                .background(shape.fill(Palette.wellFill))
                .overlay(
                    shape.strokeBorder(
                        header.isActive ? Palette.accent.opacity(0.35) : Color.clear
                    )
                )
            }
        } else {
            VStack(alignment: .leading, spacing: Space.s4) {
                transcriptBody
            }
        }
    }

    private func headerRow(_ header: Header) -> some View {
        HStack(spacing: Space.s4) {
            if header.isActive {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 5, height: 5)
            }
            Text(header.label)
                .typo(.captionMedium)
                .foregroundStyle(header.isActive ? Palette.ink : Palette.inkMuted)
            if header.isActive {
                Text("Current")
                    .typo(.micro)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s1)
                    .background(Capsule().fill(Palette.accent.opacity(0.14)))
            }
            Spacer(minLength: Space.s4)
            smallIcon(
                copied ? "checkmark" : "doc.on.doc",
                tint: copied ? Palette.signalReady : Palette.inkMuted,
                help: "Copy this version"
            ) {
                copyText()
            }
            smallIcon(
                "trash",
                tint: Palette.inkMuted,
                help: "Remove this version",
                action: header.onRemove
            )
        }
    }

    /// The body text, with any search hits marked. Unsearched this is a plain
    /// `AttributedString` carrying no attributes, so the `.secondary`
    /// foreground style below still owns every glyph.
    private var attributedText: AttributedString {
        HistorySearch.highlighted(text, query: highlight)
    }

    @ViewBuilder
    private var transcriptBody: some View {
        Text(attributedText)
            .typo(Self.transcriptStyle)
            .foregroundStyle(Palette.inkMuted)
            .textSelection(.enabled)
            .lineLimit(expanded ? nil : Self.collapsedLineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A selectable Text on macOS paints its full content height when
            // clicked, even while layout still reserves only the line-limit
            // clamp — without this it spills over "Show more". Clip it to its
            // laid-out bounds; expanded (line-limit nil) is a no-op here.
            .clipped()
            .background(truncationProbe)

        if isTruncated || expanded {
            Button(expanded ? "Show less" : "Show more") {
                withAnimation(motion.layout) { expanded.toggle() }
            }
            .buttonStyle(.plain)
            .typo(.captionMedium)
            .foregroundStyle(Palette.accent)
        }
    }

    /// Measures truncation from real glyph layout (correct for any script and
    /// window width) using two hidden copies clamped to N+1 and N lines. The
    /// extra line only adds height when the transcript overflows, so we detect
    /// truncation without ever laying out a full hour-long transcript. Both are
    /// independent of `expanded`, so expanding can't churn the measurement.
    private var truncationProbe: some View {
        ZStack {
            measuringText(lineLimit: Self.collapsedLineLimit + 1) { overflowHeight = $0 }
            measuringText(lineLimit: Self.collapsedLineLimit) { clampedHeight = $0 }
        }
        .hidden()
        .accessibilityHidden(true)
    }

    private func measuringText(lineLimit: Int?, onHeight: @escaping (CGFloat) -> Void) -> some View {
        Text(text)
            .typo(Self.transcriptStyle)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { onHeight(proxy.size.height) }
                        .onChange(of: proxy.size.height) { _, height in onHeight(height) }
                }
            )
    }

    private func copyText() {
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

    private func smallIcon(
        _ systemName: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
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

/// Quiet inline tag marking how a recording was made — "Dictation" (hotkey flow)
/// or "Conversation" (long mic+system capture). A small icon + label in tertiary
/// ink; no fill, so it sits in the metadata line rather than shouting as a chip.
struct RecordingTypeBadge: View {
    let source: RecordingHistoryEntry.Source?

    @Environment(\.increaseContrast) private var increaseContrast

    var body: some View {
        let resolved = source ?? .dictation
        HStack(spacing: Space.s1) {
            Image(systemName: resolved.symbolName)
                .font(Typo.micro)
            Text(resolved.displayName)
                .typo(.caption)
        }
        .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
    }
}

/// Compact 28-pt circular play/stop control. Filled accent while playing, a
/// subtle neutral wash at rest so it stays quiet until the row is in use.
struct PlayTile: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isPlaying ? Palette.accent : Palette.ink.opacity(0.06))
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(Typo.micro)
                    .foregroundStyle(isPlaying ? Color.white : Palette.inkMuted)
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isPlaying ? "Stop" : "Play recording")
    }
}
