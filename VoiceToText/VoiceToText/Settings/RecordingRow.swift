import AppKit
import SwiftUI

/// History's multi-select hooks for one row. Nil in Conversations, which has
/// no selection mode, so its rows keep every click they always had.
struct RecordingRowSelection {
    let isSelecting: Bool
    let isSelected: Bool
    /// A click while selecting, or a ⌘-click at any time.
    let onToggle: () -> Void
    /// A ⇧-click: selects through to this row.
    let onExtend: () -> Void
}

// MARK: - Row date

/// How much of the date a row's title spells out. The section header above a
/// row already carries the day, so a row under "Today" shows only the time.
enum RecordingRowDateStyle {
    /// "19:08" — under Today / Yesterday.
    case time
    /// "Thursday 17:20" — under This Week.
    case weekdayTime
    /// "Thu 13 Nov, 17:20" — under a month header, which carries the year.
    case dayTime
    /// "Today at 19:08", "Thu 13 Nov, 17:20", "13 Nov 2025, 17:20" — a flat
    /// list (search results) with no date header.
    case full

    /// The style for rows under one of `HistoryDateGrouping`'s sections.
    static func forSection(id: String) -> RecordingRowDateStyle {
        switch id {
        case "today", "yesterday": return .time
        case "thisWeek": return .weekdayTime
        case _ where id.hasPrefix("month."): return .dayTime
        default: return .full
        }
    }

    func label(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case .time:
            return Self.timeFormatter.string(from: date)
        case .weekdayTime:
            return Self.weekdayTimeFormatter.string(from: date)
        case .dayTime:
            return Self.dayTimeFormatter.string(from: date)
        case .full:
            if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
                return RecordingDateFormat.rowLabel(date)
            }
            if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                return Self.dayTimeFormatter.string(from: date)
            }
            return Self.dayYearTimeFormatter.string(from: date)
        }
    }

    private static func formatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    private static let weekdayTimeFormatter = formatter(template: "EEEEjmm")
    private static let dayTimeFormatter = formatter(template: "EEEdMMMjmm")
    private static let dayYearTimeFormatter = formatter(template: "dMMMyjmm")
}

// MARK: - Row

/// One saved recording, compact by default: play (or a selection checkbox),
/// then two lines — the time with its metadata, and a one-line preview of the
/// transcript — then an always-visible Copy · Favorite · ⋯ · disclosure
/// cluster. Clicking the text or the chevron opens the row: the full
/// transcript, and for a conversation the Transcript / Summary / Action Items
/// picker. One row is open at a time; the pane owns which.
///
/// A failed take is never folded away: its explanation and recovery buttons
/// always show. Shared by History and Conversations; `RecordingsList` draws the
/// plate and hairlines.
struct RecordingRow: View {
    let entry: RecordingHistoryEntry
    let isPlaying: Bool
    /// Hidden in the Conversations list, where every row is the same type.
    var showsTypeBadge: Bool = true
    var dateStyle: RecordingRowDateStyle = .full
    /// The live History search query, so matched substrings can be marked in
    /// the transcript. Empty everywhere else.
    var highlight: String = ""
    var selection: RecordingRowSelection? = nil
    /// Whether this row is open. Owned by the pane (rows are lazy, and only
    /// one is open at a time).
    @Binding var isExpanded: Bool
    /// Which view an open conversation shows. Owned by the pane for the same
    /// reason.
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
    /// The failed row's model list; built only while it is open.
    @State private var showOtherModelMenu = false
    /// The custom-prompt form, from the open row's Ask AI… button.
    @State private var showCustomPrompt = false
    /// The same form, from the ⋯ menu (anchored to it).
    @State private var showCustomPromptFromMenu = false
    @State private var showRenameSpeakers = false
    /// Draft names shown in the rename popover, seeded from the entry on open and
    /// committed to the store when the popover closes.
    @State private var speakerNameDrafts: [String: String] = [:]
    @State private var confirmingDeleteOriginal = false
    /// The pointer is over the row, or keyboard focus is on one of its
    /// secondary controls: either reveals the empty star and ⋯.
    @State private var isHovering = false
    @FocusState private var focusedControl: RowControl?

    private enum RowControl: Hashable { case star, more }

    /// Width of the leading play / checkbox column. The text column — and
    /// `RecordingsList`'s hairlines — start after it and its gap.
    static let leadingColumn: CGFloat = 28
    static let textColumnInset: CGFloat = leadingColumn + Space.s5
    /// Lines of a conversation transcript shown in an open row before Show More.
    private static let openTranscriptLineLimit = 8

    private var isRegenerating: Bool { regenerator.activeID == entry.id }

    private var isSelecting: Bool { selection?.isSelecting ?? false }

    /// The dictation that saved this row is still transcribing it. Until then
    /// the row says it is working, and offers nothing that would race it.
    private var isInFlight: Bool {
        RecordingHistoryStore.shared.inFlightIDs.contains(entry.id)
    }

    private var isConversation: Bool { entry.source == .meeting }

    /// Conversations get the full Transcript · Summary · Action Items picker.
    /// A failed one has only a placeholder to send, so it gets none.
    private var offersInsightTabs: Bool {
        isConversation && !entry.transcriptIsPlaceholder
    }

    /// Every row with a transcript opens — to the full, selectable text, and
    /// for a conversation its views — so the disclosure column is the same on
    /// every row. A failed take shows its recovery without opening.
    private var canExpand: Bool { !entry.transcriptIsPlaceholder }

    /// ⋯ shows on hover, keyboard focus or an open row, and while one of its
    /// menu's popovers is up.
    private var revealsSecondaryActions: Bool {
        isHovering || focusedControl != nil || isExpanded
            || showRegenerateMenu || showRenameSpeakers || showCustomPromptFromMenu
    }

    private var showsOpenContent: Bool { isExpanded && canExpand && !isSelecting }

    private var faintInk: Color {
        Palette.inkFaint(increaseContrast: increaseContrast)
    }

    /// Canonical speaker labels present in the stored transcript; non-empty
    /// only for a diarized recording.
    private var speakerLabels: [String] { SpeakerRelabeler.speakerLabels(in: entry.transcript) }

    /// Whether to offer Name Speakers. Every label starts "Speaker ", so a
    /// plain substring check spares the line-by-line parse on most rows.
    private var hasSpeakerLabels: Bool {
        entry.transcript.contains("Speaker ") && !speakerLabels.isEmpty
    }

    /// Applies the entry's speaker-name mapping for display and copy — the
    /// stored string keeps its canonical "Speaker N" labels.
    private func displayText(_ text: String) -> String {
        SpeakerRelabeler.apply(names: entry.speakerNames ?? [:], to: text)
    }

    var body: some View {
        // Parsed once per pass: the ⋯ menu and the context menu both need it.
        let hasSpeakers = hasSpeakerLabels
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .center, spacing: Space.s5) {
                if let selection, selection.isSelecting {
                    selectionCheckbox(selection)
                } else {
                    IconButton(
                        isPlaying ? "stop.fill" : "play.fill",
                        label: isPlaying
                            ? "Stop playback"
                            : "Play recording from \(RecordingDateFormat.rowLabel(entry.createdAt))",
                        tint: isPlaying ? Palette.ink : nil,
                        action: onPlay
                    )
                }

                summaryColumn
                    .frame(maxWidth: .infinity, alignment: .leading)

                trailingActions(hasSpeakers: hasSpeakers)
            }

            detailSection
        }
        .padding(.vertical, Space.s4 + Space.s1)
        .padding(.horizontal, Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if selection?.isSelected == true, isSelecting {
                ConcentricRectangle(inset: Space.s2) { $0.fill(Palette.wellFill) }
                    .padding(Space.s2)
            }
        }
        .contentShape(Rectangle())
        // Selecting, the whole row is one target and nothing under it plays,
        // opens or selects text.
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.shift) {
                        selection?.onExtend()
                    } else {
                        selection?.onToggle()
                    }
                }
                .allowsHitTesting(isSelecting)
                .accessibilityHidden(true)
        }
        .gesture(
            TapGesture().modifiers(.command).onEnded { selection?.onToggle() },
            including: selection != nil && !isSelecting ? .all : .subviews
        )
        .gesture(
            TapGesture().modifiers(.shift).onEnded { selection?.onExtend() },
            including: selection != nil && !isSelecting ? .all : .subviews
        )
        .contextMenu {
            if !isSelecting { rowMenu(hasSpeakers: hasSpeakers) }
        }
        .onHover { isHovering = $0 }
        .animation(motion.hover, value: revealsSecondaryActions)
        // The row's controls as VoiceOver actions, so none needs hunting for.
        .accessibilityActions {
            if !isSelecting {
                Button(isPlaying ? "Stop playback" : "Play recording", action: onPlay)
                if !entry.transcriptIsPlaceholder {
                    Button("Copy transcript", action: copyActiveTranscript)
                    Button(isExpanded ? "Close recording" : "Open recording", action: toggleExpanded)
                }
                Button(entry.isFavorited ? "Remove from Favorites" : "Add to Favorites", action: onToggleFavorite)
                if !isInFlight {
                    Button("Delete recording", role: .destructive, action: onDelete)
                }
            }
        }
        .confirmationDialog(
            "Delete the original recording?",
            isPresented: $confirmingDeleteOriginal
        ) {
            Button("Delete Original", role: .destructive, action: deleteOriginal)
        } message: {
            Text("The recording with silence removed and its transcript stay. This can't be undone.")
        }
        .onDisappear { copyResetTask?.cancel() }
    }

    // MARK: - Summary (the closed row)

    /// The two lines every row shows. When the row can open, they are the
    /// button that opens it.
    @ViewBuilder
    private var summaryColumn: some View {
        let lines = VStack(alignment: .leading, spacing: Space.s1) {
            titleLine
            secondLine
        }
        if canExpand && !isSelecting {
            Button(action: summaryClicked) {
                lines.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Closes this recording" : expandHint)
        } else {
            lines
        }
    }

    private var expandHint: String {
        offersInsightTabs ? "Shows the transcript, summary and action items" : "Shows the full transcript"
    }

    private func toggleExpanded() {
        withAnimation(motion.layout) { isExpanded.toggle() }
    }

    /// A plain click opens the row; ⌘- and ⇧-click keep selecting it, as they
    /// do anywhere else on the row (the text is a button, so the row's own
    /// modifier taps never see them).
    private func summaryClicked() {
        let flags = NSEvent.modifierFlags
        if let selection, flags.contains(.command) {
            selection.onToggle()
        } else if let selection, flags.contains(.shift) {
            selection.onExtend()
        } else {
            toggleExpanded()
        }
    }

    /// "19:08  🎙 6 sec · GPT Transcribe · OpenAI  [☑ 3 action items]".
    /// VoiceOver reads the full date, since the visible time leans on the
    /// section header for the day.
    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            Text(dateStyle.label(entry.createdAt))
                .typo(.headline)
                .foregroundStyle(Palette.ink)
                .fixedSize()
                .accessibilityLabel(RecordingDateFormat.rowLabel(entry.createdAt))

            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                if showsTypeBadge {
                    Image(systemName: (entry.source ?? .dictation).symbolName)
                        .font(Typo.micro)
                        .accessibilityLabel((entry.source ?? .dictation).displayName)
                }
                Text(metaLine)
                    .typo(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(faintInk)
            .help(metaLine)
        }
        .accessibilityElement(children: .combine)
    }

    /// "31 min · 3 action items · GPT Transcribe · OpenAI", most useful first so
    /// a narrow row loses the provider, not the count; the kind is the glyph
    /// (VoiceOver names it) and the whole line is the tooltip. A row without
    /// a transcript leaves its model out — the notice names it where it can
    /// be acted on.
    private var metaLine: String {
        var parts = [Self.durationLabel(entry.durationSeconds)]
        if let count = entry.actionItems?.items.count, count > 0 {
            parts.append(count == 1 ? "1 action item" : "\(count) action items")
        }
        if !entry.transcriptIsPlaceholder, let model = modelLabel {
            parts.append(model)
        }
        return parts.joined(separator: " · ")
    }

    /// "6 sec", "31 min", "1 h 05 min" — words, so a length never reads as
    /// a clock time beside the row's own time.
    static func durationLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) sec" }
        if total < 3600 { return "\(max(1, Int((Double(total) / 60).rounded()))) min" }
        let minutes = (total % 3600) / 60
        return "\(total / 3600) h \(minutes < 10 ? "0" : "")\(minutes) min"
    }

    /// "GPT Transcribe · OpenAI" or "Parakeet TDT v3 · On this Mac" — the
    /// Models pane's spelling, so a cloud model always says where audio went.
    private var modelLabel: String? {
        if let id = entry.modelId, let model = ModelCatalog.model(for: id) {
            return model.nameWithSource
        }
        let stored = entry.modelName ?? entry.modelId
        return stored?.isEmpty == false ? stored : nil
    }

    /// The closed row's second line: the transcript's first line, or what the
    /// row is waiting on. Hidden while open — the transcript is right below.
    @ViewBuilder
    private var secondLine: some View {
        if entry.transcriptIsPlaceholder {
            if isInFlight {
                transcribingNotice
            } else if let status = HistorySearch.untranscribedStatus(of: entry) {
                failureSentence(status)
            }
        } else if !showsOpenContent {
            previewLine
        }
    }

    /// One line: the summary's first sentence when a conversation has one (the
    /// best handle on which meeting it was), otherwise the transcript. While
    /// searching it is the transcript, starting near the first match.
    private var previewLine: some View {
        Text(HistorySearch.highlighted(previewText, query: highlight))
            .typo(.body)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Works on a window of a few hundred characters, never the whole
    /// transcript: an hour-long conversation is one line here.
    private var previewText: String {
        let isSearching = HistorySearch.isActive(highlight)
        if isConversation, !isSearching, let summary = entry.summary?.text,
           let sentence = Self.firstSentence(of: String(summary.prefix(Self.previewWindow))) {
            return sentence
        }
        let transcript = entry.transcript
        var start = transcript.startIndex
        if isSearching,
           let hit = HistorySearch.terms(in: highlight)
            .compactMap({ transcript.range(of: $0, options: HistorySearch.options)?.lowerBound })
            .min(),
           transcript.distance(from: transcript.startIndex, to: hit) > 60 {
            let lead = transcript.index(hit, offsetBy: -24, limitedBy: transcript.startIndex) ?? transcript.startIndex
            start = transcript[lead...].firstIndex(of: " ").map { transcript.index(after: $0) } ?? lead
        }
        let end = transcript.index(start, offsetBy: Self.previewWindow, limitedBy: transcript.endIndex) ?? transcript.endIndex
        let window = displayText(String(transcript[start..<end]))
            .replacingOccurrences(of: "\n", with: " ")
        return start == transcript.startIndex ? window : "…" + window
    }

    /// Characters the preview reads; far more than one line ever shows.
    private static let previewWindow = 300

    /// The text up to and including its first ". ", or nil for an empty one.
    static func firstSentence(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !trimmed.isEmpty else { return nil }
        guard let end = trimmed.range(of: ". ") else { return trimmed }
        return String(trimmed[..<end.lowerBound]) + "."
    }

    /// Stands in for the play tile while selecting, at the same size so the
    /// row doesn't shift. A real toggle named by the row's date, so VoiceOver
    /// and the keyboard can select without the click target over the row.
    private func selectionCheckbox(_ selection: RecordingRowSelection) -> some View {
        let label = RecordingDateFormat.rowLabel(entry.createdAt)
        return Toggle(label, isOn: Binding(
            get: { selection.isSelected },
            set: { _ in selection.onToggle() }
        ))
        .toggleStyle(.checkbox)
        .labelsHidden()
        .accessibilityLabel(label)
        .frame(width: Self.leadingColumn, height: Self.leadingColumn)
    }

    // MARK: - Actions

    /// ⋯ · star · Copy · disclosure. The star (outline or filled), Copy and the
    /// disclosure are always shown; ⋯ appears on hover, keyboard focus or an
    /// open row (its slot is kept, so columns line up down the list).
    /// Everything is also in the context menu and the VoiceOver actions. A row
    /// still in flight offers neither re-transcription nor delete.
    @ViewBuilder
    private func trailingActions(hasSpeakers: Bool) -> some View {
        if isSelecting {
            if entry.isFavorited {
                Image(systemName: "star.fill")
                    .font(Typo.body)
                    .foregroundStyle(Palette.favorite)
                    .frame(width: FormMetrics.iconButton, height: FormMetrics.iconButton)
                    .accessibilityLabel("Favorite")
            }
        } else {
            HStack(spacing: Space.s1) {
                if isRegenerating {
                    regenerateProgress
                }
                IconMenu(label: "More actions for this recording") { rowMenu(hasSpeakers: hasSpeakers) }
                    .focused($focusedControl, equals: .more)
                    .opacity(revealsSecondaryActions ? 1 : 0)
                    .popover(isPresented: $showRegenerateMenu, arrowEdge: .bottom) {
                        regeneratePopup
                    }
                    .popover(isPresented: $showRenameSpeakers, arrowEdge: .bottom) {
                        speakerNamePopover
                            .onDisappear { onRenameSpeakers(speakerNameDrafts) }
                    }
                    .popover(isPresented: $showCustomPromptFromMenu, arrowEdge: .bottom) {
                        customPromptPopover { showCustomPromptFromMenu = false }
                    }
                IconToggle(
                    isOn: Binding(get: { entry.isFavorited }, set: { _ in onToggleFavorite() }),
                    on: ("star.fill", "Remove from Favorites"),
                    off: ("star", "Add to Favorites"),
                    onTint: Palette.favorite
                )
                .focused($focusedControl, equals: .star)
                if entry.transcriptIsPlaceholder {
                    actionSlot
                } else {
                    IconButton(
                        copied ? "checkmark" : "doc.on.doc",
                        label: copied ? "Copied" : "Copy transcript",
                        tint: copied ? Palette.signalReady : nil,
                        action: copyActiveTranscript
                    )
                }
                if canExpand {
                    IconButton(
                        isExpanded ? "chevron.up" : "chevron.down",
                        label: isExpanded ? "Close recording" : (offersInsightTabs ? "Open conversation" : "Show full transcript"),
                        action: toggleExpanded
                    )
                } else {
                    actionSlot
                }
            }
        }
    }

    /// An empty 28pt slot, so a row without a control there keeps the column.
    private var actionSlot: some View {
        Color.clear
            .frame(width: FormMetrics.iconButton, height: FormMetrics.iconButton)
            .accessibilityHidden(true)
    }

    /// The ⋯ menu, mirrored as the row's context menu.
    @ViewBuilder
    private func rowMenu(hasSpeakers: Bool) -> some View {
        Button("Copy Transcript", action: copyActiveTranscript)
            .disabled(entry.transcriptIsPlaceholder)
        Button(entry.isFavorited ? "Remove from Favorites" : "Add to Favorites", action: onToggleFavorite)

        Divider()

        if !isInFlight {
            Button(entry.transcriptIsPlaceholder ? "Transcribe With…" : "Transcribe Again With…") {
                presentAfterMenu { showRegenerateMenu = true }
            }
            .disabled(regenerator.isRunning)
        }
        if hasSpeakers {
            Button("Name Speakers…") {
                speakerNameDrafts = entry.speakerNames ?? [:]
                presentAfterMenu { showRenameSpeakers = true }
            }
        }

        if !entry.transcriptIsPlaceholder {
            Section("AI · sends the transcript to OpenAI") {
                Button(entry.hasInsight(.summary) ? "Regenerate Summary" : "Summarize") {
                    generate(.summary)
                }
                .disabled(insights.isRunning(entryID: entry.id, kind: .summary))
                Button(entry.hasInsight(.actionItems) ? "Regenerate Action Items" : "Find Action Items") {
                    generate(.actionItems)
                }
                .disabled(insights.isRunning(entryID: entry.id, kind: .actionItems))
                Button("Ask AI…") {
                    presentAfterMenu { showCustomPromptFromMenu = true }
                }
            }
        }

        Divider()

        Button("Show in Finder", action: revealAudio)

        if let original = entry.originalAudio {
            Section("Original · \(Self.durationLabel(original.durationSeconds))") {
                Button("Play Original", action: playOriginal)
                Button("Show Original in Finder", action: revealOriginal)
                Button("Delete Original…", role: .destructive) {
                    presentAfterMenu { confirmingDeleteOriginal = true }
                }
            }
        }

        if !isInFlight {
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    /// A popover asked for while its menu is still closing is dropped, so the
    /// flag is set a beat after the menu goes away.
    private func presentAfterMenu(_ present: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            present()
        }
    }

    private func revealAudio() {
        let url = RecordingHistoryStore.shared.audioURL(for: entry)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            HistoryFolder.reveal()
        }
    }

    /// The untouched recording "Remove silence" kept beside this one. Played
    /// under the row's id, so the row's play button stops it.
    private func playOriginal() {
        guard let url = RecordingHistoryStore.shared.originalAudioURL(for: entry) else { return }
        HistoryAudioPlayer.shared.play(url: url, id: entry.id)
    }

    private func revealOriginal() {
        guard let url = RecordingHistoryStore.shared.originalAudioURL(for: entry),
              FileManager.default.fileExists(atPath: url.path) else {
            HistoryFolder.reveal()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func deleteOriginal() {
        let player = HistoryAudioPlayer.shared
        if player.playingID == entry.id { player.stop() }
        RecordingHistoryStore.shared.removeOriginalAudio(entryID: entry.id)
    }

    private func copyActiveTranscript() {
        guard !entry.transcriptIsPlaceholder else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(displayText(entry.transcript), forType: .string)
        copied = true
        AccessibilityNotification.Announcement("Copied").post()
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    /// Spinner, plus "3/8" for a long recording, while this row re-transcribes.
    private var regenerateProgress: some View {
        HStack(spacing: Space.s2) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: Space.s6, height: Space.s6)
            if regenerator.totalChunks > 1 {
                Text("\(regenerator.transcribedChunks)/\(regenerator.totalChunks)")
                    .typo(.mono)
                    .contentTransition(.numericText())
                    .foregroundStyle(faintInk)
            }
        }
        .frame(minHeight: FormMetrics.iconButton)
        .padding(.horizontal, Space.s2)
        .help("Transcribing again…")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcribing again")
    }

    // MARK: - Detail (under the closed row)

    /// What sits under the two lines: the open row's content, a failed take's
    /// recovery buttons (always), and any job's progress or failure.
    @ViewBuilder
    private var detailSection: some View {
        let downloading = isRegenerating ? regenerator.downloadingModelID : nil
        let regenFailure = regenerator.failure.flatMap { $0.id == entry.id ? $0.message : nil }
        let showsRecovery = entry.transcriptIsPlaceholder && !isInFlight && !isRegenerating
        if showsOpenContent || showsRecovery || downloading != nil || regenFailure != nil || !failedKinds.isEmpty {
            VStack(alignment: .leading, spacing: Space.s4) {
                if showsOpenContent {
                    openContent
                }
                if showsRecovery {
                    recoveryButtons
                        .disabled(regenerator.isRunning)
                }
                if let downloading {
                    modelDownloadNotice(downloading)
                }
                insightFailures
                if let regenFailure {
                    failureNote(regenFailure) {
                        Button("Dismiss") { regenerator.dismissFailure() }
                            .buttonTier(.secondary)
                            .controlSize(.small)
                    }
                }
            }
            .padding(.leading, Self.textColumnInset)
            .transition(.opacity)
        }
    }

    /// The open row: the full transcript, or — for a conversation, or a
    /// dictation that has an insight — a segmented picker over Transcript /
    /// Summary / Action Items / results, with Ask AI… beside it.
    @ViewBuilder
    private var openContent: some View {
        let tabs = InsightTab.visible(for: entry, generator: insights, includingBuiltIns: offersInsightTabs)
        VStack(alignment: .leading, spacing: Space.s4) {
            if tabs.count > 1 {
                HStack(alignment: .center, spacing: Space.s4) {
                    InsightTabBar(entry: entry, tabs: tabs, selection: tabBinding(in: tabs))
                    Spacer(minLength: Space.s4)
                    if offersInsightTabs {
                        askAIButton
                    }
                }
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
        }
        .animation(motion.layout, value: shownTab(in: tabs))
    }

    private var askAIButton: some View {
        Button {
            showCustomPrompt = true
        } label: {
            Label("Ask AI…", systemImage: "sparkles")
        }
        .buttonTier(.secondary)
        .controlSize(.small)
        .fixedSize()
        .help("Run your own instruction on this transcript. \(Self.sendsTranscript)")
        .popover(isPresented: $showCustomPrompt, arrowEdge: .bottom) {
            customPromptPopover { showCustomPrompt = false }
        }
    }

    /// `.id(kind)` so two custom results don't share one pane's state (its
    /// copy confirmation) across a tab swap.
    private func insightPane(_ kind: InsightKind) -> some View {
        InsightPane(
            entry: entry,
            kind: kind,
            sendsTranscriptNote: Self.sendsTranscript,
            onToggleActionItem: onToggleActionItem,
            onRemove: { onRemoveInsight(kind) },
            onRegenerate: { generate(kind) }
        )
        .id(kind)
    }

    /// The tab actually drawn. A remembered choice can outlive what it points
    /// at, so a tab that is no longer on offer falls back to the transcript.
    private func shownTab(in tabs: [InsightTab]) -> InsightTab {
        tabs.contains(selectedTab) ? selectedTab : .transcript
    }

    private func tabBinding(in tabs: [InsightTab]) -> Binding<InsightTab> {
        Binding(
            get: { shownTab(in: tabs) },
            set: { selectedTab = $0 }
        )
    }

    /// Every insight leaves the Mac, even for a recording transcribed locally.
    private static let sendsTranscript = "Sends the transcript to OpenAI (\(ActionRunner.modelId))."

    /// Starts a generation and opens the row on its view right away, where
    /// the running tab shows progress. Finishing only selects the result: by
    /// then the user may have closed this row or opened another. Started from
    /// the action rather than a `.task`: rows are lazy, and scrolling this one
    /// away must not cancel a paid-for request.
    private func generate(_ kind: InsightKind) {
        selectedTab = kind.tab
        withAnimation(motion.layout) { isExpanded = true }
        Task {
            if await insights.generate(entry: entry, kind: kind) {
                selectedTab = kind.tab
            }
        }
    }

    /// Runs a newly typed instruction and opens the row on the view it landed
    /// in, by the id the generator hands back.
    private func runCustom(instruction: String) {
        withAnimation(motion.layout) { isExpanded = true }
        Task {
            guard let id = await insights.generateCustom(
                entry: entry,
                instruction: instruction,
                replacing: nil
            ) else { return }
            selectedTab = .custom(id)
        }
    }

    private func customPromptPopover(close: @escaping () -> Void) -> some View {
        CustomPromptPopover(
            usedCount: insights.usedCustomSlots(for: entry),
            maxCount: RecordingHistoryEntry.maxCustomInsights,
            failureMessage: insights.customFailure(entryID: entry.id),
            onDismissFailure: { insights.dismissCustomFailure(entryID: entry.id) }
        ) { instruction in
            close()
            runCustom(instruction: instruction)
        }
    }

    // MARK: - Failures

    /// One note per failing job: what went wrong, and the way out of it.
    @ViewBuilder
    private var insightFailures: some View {
        ForEach(failedKinds, id: \.self) { kind in
            if let message = insights.failure(entryID: entry.id, kind: kind) {
                failureNote(message) {
                    Button("Dismiss") { dismissFailure(kind) }
                        .buttonTier(.secondary)
                        .controlSize(.small)
                        .help("Hide this message")
                    // A missing API key is the one failure this row cannot fix.
                    if !insights.hasAPIKey {
                        Button("Open Cloud") { SettingsRouter.shared.pendingSection = .cloud }
                            .buttonStyle(TextLinkButtonStyle(font: Typo.captionMedium))
                            .help("Open Cloud settings to add an OpenAI API key")
                    }
                }
            }
        }
    }

    private func failureNote<Actions: View>(
        _ message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Typo.caption)
                .foregroundStyle(Palette.signalWarn)
                .accessibilityHidden(true)
            Text(message)
                .typo(.caption)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
    }

    /// Which jobs this row has a failure for, in a stable order: built-ins,
    /// then custom results in tab order, then refused new results (stored
    /// nowhere, so this is the only place they can be read).
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
        ordered += customFailures.keys
            .filter { !storedIDs.contains($0) }
            .sorted { $0.uuidString < $1.uuidString }
            .map(InsightKind.custom)
        return ordered
    }

    /// A custom failure is parked on its job and on the recording (where the
    /// form reads it), so dismissing it clears both.
    private func dismissFailure(_ kind: InsightKind) {
        insights.dismissFailure(entryID: entry.id, kind: kind)
        if kind.isCustom {
            insights.dismissCustomFailure(entryID: entry.id)
        }
    }

    // MARK: - Transcript

    /// The open row's transcript: all of a dictation; a conversation's first
    /// lines with Show More. With alternate versions, one labelled block each.
    @ViewBuilder
    private var transcriptSection: some View {
        let lineLimit = isConversation ? Self.openTranscriptLineLimit : nil
        if entry.hasAlternateTranscripts {
            VStack(alignment: .leading, spacing: Space.s4) {
                ForEach(entry.transcriptVariants) { variant in
                    TranscriptBlockView(
                        text: displayText(variant.text),
                        highlight: highlight,
                        collapsedLineLimit: lineLimit,
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
                collapsedLineLimit: lineLimit,
                header: nil
            )
        }
    }

    private var transcribingNotice: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: Space.s5, height: Space.s5)
            Text("Transcribing…")
                .typo(.body)
                .foregroundStyle(Palette.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Downloading Parakeet TDT v3 · 42%" while this row's re-transcription
    /// waits on a model that isn't on this Mac yet.
    private func modelDownloadNotice(_ modelId: String) -> some View {
        let name = ModelCatalog.model(for: modelId)?.displayName ?? modelId
        let readiness = ModelRegistry.shared.readiness(for: modelId)
        let text: String
        switch readiness {
        case .preparing(let fraction, _) where !readiness.isLoadingOrCompiling:
            text = FailureCardCopy.historyDownloading(modelName: name, fraction: fraction)
        case .preparing, .installed:
            text = "\(FailureCardCopy.preparePhaseTitle(isLoading: true)) \(name)"
        case .notInstalled, .failed:
            text = FailureCardCopy.historyDownloading(modelName: name, fraction: nil)
        }
        return Text(text)
            .typo(.caption)
            .monospacedDigit()
            .foregroundStyle(Palette.inkMuted)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Not transcribed

    /// "⚠ Not transcribed. You're offline…", in the failure card's own words.
    /// "⚠ Not transcribed. You're offline." — the reason's first sentence;
    /// the buttons below say the rest. The whole message is the tooltip and
    /// what VoiceOver reads.
    private func failureSentence(_ status: RecordingHistoryEntry.Status) -> some View {
        let reason = Self.firstSentence(of: status.message) ?? status.message
        return HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Typo.caption)
                .foregroundStyle(Palette.signalWarn)
                .accessibilityHidden(true)
            (Text("\(HistorySearch.notTranscribedLabel). ").foregroundStyle(Palette.ink)
                + Text(HistorySearch.highlighted(reason, query: highlight)).foregroundStyle(Palette.inkMuted))
                .typo(.body)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(status.message)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(HistorySearch.notTranscribedLabel). \(status.message)")
    }

    /// One recommended way out, prominent, then a quieter second choice and
    /// every other model in a menu. Worked out once per pass and handed to
    /// each candidate layout.
    private var recoveryButtons: some View {
        let plan = recoveryPlan
        return VStack(alignment: .leading, spacing: Space.s3) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s4) {
                    recoveryLead(plan)
                    recoverySecondary(plan)
                    otherModelButton
                }
                VStack(alignment: .leading, spacing: Space.s3) {
                    recoveryLead(plan)
                    HStack(spacing: Space.s4) {
                        recoverySecondary(plan)
                        otherModelButton
                    }
                }
            }
            .controlSize(.regular)
            // Attached once, outside the candidate layouts that each hold a
            // copy of the button; anchored at the trailing end, where Other
            // Model sits in either layout.
            .popover(isPresented: $showOtherModelMenu, attachmentAnchor: .point(.bottomTrailing), arrowEdge: .bottom) {
                DropdownPopup(
                    sections: regenerateModelSections,
                    selected: nil,
                    width: 280
                ) { modelId in
                    showOtherModelMenu = false
                    regenerate(with: modelId)
                }
            }
            if let note = plan.note {
                Text(note)
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func recoveryLead(_ plan: RecoveryPlan) -> some View {
        if let lead = plan.lead {
            recoveryButton(lead).buttonTier(.primary)
        }
    }

    @ViewBuilder
    private func recoverySecondary(_ plan: RecoveryPlan) -> some View {
        if let secondary = plan.secondary {
            recoveryButton(secondary).buttonTier(.secondary)
        }
    }

    private func recoveryButton(_ choice: RecoveryChoice) -> some View {
        Button {
            regenerate(with: choice.modelId)
        } label: {
            if let systemImage = choice.systemImage {
                Label(choice.title, systemImage: systemImage)
            } else {
                Text(choice.title)
            }
        }
        .fixedSize()
        .help(choice.help)
    }

    private struct RecoveryChoice {
        let title: String
        var systemImage: String?
        let help: String
        let modelId: String
    }

    private struct RecoveryPlan {
        var lead: RecoveryChoice?
        var secondary: RecoveryChoice?
        /// Said under the buttons, e.g. that the model on this Mac may not
        /// know every language the user speaks.
        var note: String?
    }

    /// Which model leads. The one on this Mac leads when it knows the user's
    /// languages, or when the provider is out of credit (a retry would only be
    /// refused again) — the dictation card's rule. A local model that doesn't
    /// know every language the user speaks is offered second, and says so.
    private var recoveryPlan: RecoveryPlan {
        guard let model = transcribeAgainModel else { return RecoveryPlan() }
        let retry = RecoveryChoice(
            title: model.isCloud
                ? FailureCardCopy.historyRetryTitle(cloudModelName: model.sectionedDisplayName)
                : "Transcribe with \(model.displayName)",
            help: "Try \(model.displayName) again",
            modelId: model.id
        )
        guard let provider = model.backend.cloudProvider,
              let local = localAlternative(to: model)
        else { return RecoveryPlan(lead: retry) }

        let outOfCredit = CloudCreditStatus.shared.isOutOfCredit(provider)
        var coversLanguages = true
        if case .ready(_, let covers) = local.fallback { coversLanguages = covers }
        let localChoice = RecoveryChoice(
            title: FailureCardCopy.historyLocalTitle(local.fallback, modelName: local.model.displayName),
            help: coversLanguages
                ? "\(local.model.displayName) runs on this Mac — free, private and works offline"
                : "\(local.model.displayName) runs on this Mac, but may not know every language you speak",
            modelId: local.model.id
        )
        // Groq's Whisper shares its name with the local one, so the retry
        // keeps "(Groq)" when the two would read alike.
        let retryName = model.sectionedDisplayName == local.model.displayName
            ? model.displayName
            : model.sectionedDisplayName
        let namedRetry = RecoveryChoice(
            title: FailureCardCopy.historyRetryTitle(cloudModelName: retryName),
            help: outOfCredit ? "Try \(model.displayName) again once your balance is topped up" : "Try \(model.displayName) again",
            modelId: model.id
        )
        let note = coversLanguages
            ? nil
            : "\(local.model.displayName) may not know every language you speak."
        return coversLanguages || outOfCredit
            ? RecoveryPlan(lead: localChoice, secondary: namedRetry, note: note)
            : RecoveryPlan(lead: namedRetry, secondary: localChoice, note: note)
    }

    /// Every other model, in the same list as Transcribe Again With…: "On
    /// this Mac" first, then each provider, saying what picking one takes
    /// first (a download, a key). The list is built only while the popover
    /// (on `recoveryButtons`) is open — it reads the disk, and a failed row
    /// re-renders on every download tick.
    private var otherModelButton: some View {
        Button {
            showOtherModelMenu = true
        } label: {
            HStack(spacing: Space.s2) {
                Text("Other Model")
                Image(systemName: "chevron.down")
                    .font(Typo.micro)
                    .accessibilityHidden(true)
            }
        }
        .buttonTier(.secondary)
        .fixedSize()
        .help("Transcribe with another model. Models on this Mac work offline and cost nothing.")
    }

    private func regenerate(with modelId: String) {
        Task { await regenerator.regenerate(entry: entry, modelId: modelId) }
    }

    /// The model on this Mac to lead with when the take was meant for a cloud
    /// model: one already downloaded, or — while that provider is out of
    /// credit — one to download first, the same choice the dictation card
    /// makes. Reads only cached state, so it is safe in the body.
    private func localAlternative(
        to model: ModelDescriptor
    ) -> (fallback: DictationTakePolicy.LocalFallback, model: ModelDescriptor)? {
        guard let provider = model.backend.cloudProvider else { return nil }
        let canDownload = CloudCreditStatus.shared.isOutOfCredit(provider)
        guard let fallback = ModelRegistry.shared.localFallback(replacing: model.id, canDownload: canDownload),
              let local = ModelCatalog.model(for: fallback.modelID)
        else { return nil }
        return (fallback, local)
    }

    /// The model the take was meant for while it still exists, otherwise
    /// the active dictation model.
    private var transcribeAgainModel: ModelDescriptor? {
        if let id = entry.modelId, let model = ModelCatalog.model(for: id) { return model }
        return ModelRegistry.shared.activeModel
    }

    private func modelLabel(for variant: TranscriptVariant) -> String {
        variant.modelName ?? variant.modelId ?? "Transcript"
    }

    // MARK: - Popovers

    /// "Transcribe again with…": every model except the live ones, grouped
    /// "On this Mac" / by provider. No checkmark on a row without a transcript:
    /// its model is the one that failed.
    private var regeneratePopup: some View {
        DropdownPopup(
            sections: regenerateModelSections,
            selected: entry.transcriptIsPlaceholder ? nil : entry.modelId,
            width: 280
        ) { modelId in
            showRegenerateMenu = false
            regenerate(with: modelId)
        }
    }

    /// The models on this Mac come first, downloaded ones ahead of the rest;
    /// what picking one will take first (a download, an API key) is said on
    /// its row. Downloaded is asked of the disk (`ModelStorage.isDownloaded`),
    /// not of readiness, which reads `.preparing` while a model on disk loads.
    private var regenerateModelSections: [DropdownSection<String>] {
        let registry = ModelRegistry.shared
        return ModelGroup.sections(of: ModelCatalog.all.filter { !$0.isRealtime }).map { section in
            if let provider = section.group.provider {
                let detail = provider.hasAPIKey ? nil : "Needs an API key"
                return DropdownSection(
                    header: section.group.title,
                    items: section.models.map { DropdownItem(value: $0.id, title: $0.sectionedDisplayName, detail: detail) }
                )
            }
            let onDisk = Set(section.models.filter {
                ModelStorage.isDownloaded($0, readiness: registry.readiness(for: $0.id))
            }.map(\.id))
            let installed = section.models.filter { onDisk.contains($0.id) }
            let notInstalled = section.models.filter { !onDisk.contains($0.id) }
            return DropdownSection(
                header: section.group.title,
                items: installed.map { DropdownItem(value: $0.id, title: $0.sectionedDisplayName) }
                    + notInstalled.map {
                        DropdownItem(value: $0.id, title: $0.sectionedDisplayName, detail: Self.downloadDetail($0))
                    }
            )
        }
    }

    /// "Download · ~470 MB" for a local model that isn't on disk yet.
    private static func downloadDetail(_ model: ModelDescriptor) -> String {
        guard model.approxSizeMB > 0 else { return "Not downloaded" }
        return "Download · ~\(model.approxSizeBytes.formattedDiskSize)"
    }

    /// One field per canonical speaker. Clearing a field reverts that speaker
    /// to "Speaker N"; giving two the same name merges them. Names commit when
    /// the popover closes.
    private var speakerNamePopover: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Text("Name Speakers")
                .typo(.headline)
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: Space.s4) {
                ForEach(speakerLabels, id: \.self) { label in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(label)
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                        TextField(label, text: speakerNameBinding(for: label), prompt: Text("Name"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .accessibilityLabel("Name for \(label)")
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { showRenameSpeakers = false }
                    .buttonTier(.primary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s6)
        .frame(width: 240)
        .glassSurface(in: Rectangle())
    }

    private func speakerNameBinding(for label: String) -> Binding<String> {
        Binding(
            get: { speakerNameDrafts[label] ?? "" },
            set: { speakerNameDrafts[label] = $0 }
        )
    }
}

// MARK: - Transcript block

/// One transcript: selectable text, clamped to `collapsedLineLimit` lines with
/// Show More (nil shows it all). With a `header` (a recording with more than
/// one version) it is a labeled well with per-version copy and remove.
struct TranscriptBlockView: View {
    let text: String
    /// History's live search query; matches are washed in the accent.
    var highlight: String = ""
    var collapsedLineLimit: Int? = 3
    let header: Header?

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

    /// Shared by the visible body and the measuring probes, so truncation is
    /// measured against exactly what's drawn.
    private static let transcriptStyle: Typo.Style = .body

    /// Truncated when one extra line would make the transcript taller.
    private var isTruncated: Bool { collapsedLineLimit != nil && overflowHeight > clampedHeight + 1 }

    var body: some View {
        content
            .onDisappear { copyResetTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        if let header {
            ConcentricRectangle(inset: Space.s3) { shape in
                VStack(alignment: .leading, spacing: Space.s2) {
                    headerRow(header)
                    transcriptBody
                }
                .padding(.leading, Space.s5)
                .padding(.trailing, Space.s2)
                .padding(.vertical, Space.s3)
                .background(shape.fill(Palette.wellFill))
            }
        } else {
            VStack(alignment: .leading, spacing: Space.s2) {
                transcriptBody
            }
        }
    }

    private func headerRow(_ header: Header) -> some View {
        HStack(spacing: Space.s4) {
            Text(header.label)
                .typo(.captionMedium)
                .foregroundStyle(header.isActive ? Palette.ink : Palette.inkMuted)
            if header.isActive {
                BadgeLabel("Current")
            }
            Spacer(minLength: Space.s4)
            IconButton(
                copied ? "checkmark" : "doc.on.doc",
                label: copied ? "Copied" : "Copy this version",
                tint: copied ? Palette.signalReady : nil
            ) {
                copyText()
            }
            IconButton("trash", label: "Remove this version", action: header.onRemove)
        }
    }

    private var attributedText: AttributedString {
        HistorySearch.highlighted(text, query: highlight)
    }

    @ViewBuilder
    private var transcriptBody: some View {
        Text(attributedText)
            .typo(Self.transcriptStyle)
            .foregroundStyle(Palette.ink)
            .textSelection(.enabled)
            .lineLimit(expanded ? nil : collapsedLineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A selectable Text paints its full height when clicked, even while
            // layout reserves only the clamp — clip it to its laid-out bounds.
            .clipped()
            .background {
                if let collapsedLineLimit { truncationProbe(collapsedLineLimit) }
            }

        if isTruncated || expanded {
            ShowMoreButton(expanded: expanded) {
                withAnimation(motion.layout) { expanded.toggle() }
            }
        }
    }

    /// Two hidden copies clamped to N+1 and N lines: the extra line only adds
    /// height when the transcript overflows, so truncation is detected without
    /// laying out a whole hour-long transcript.
    private func truncationProbe(_ limit: Int) -> some View {
        ZStack {
            measuringText(lineLimit: limit + 1) { overflowHeight = $0 }
            measuringText(lineLimit: limit) { clampedHeight = $0 }
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
        AccessibilityNotification.Announcement("Copied").post()
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

/// "Show More ⌄" / "Show Less ⌃" — an in-place action, so a small bordered
/// button rather than a link (links are for going somewhere).
struct ShowMoreButton: View {
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s1) {
                Text(expanded ? "Show Less" : "Show More")
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(Typo.micro)
                    .accessibilityHidden(true)
            }
        }
        .buttonTier(.secondary)
        .controlSize(.small)
    }
}
