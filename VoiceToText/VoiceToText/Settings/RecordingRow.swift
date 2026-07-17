import AppKit
import SwiftUI

/// A single saved-recording row: leading play tile, timestamp + metadata, copy
/// and delete controls, and the transcript(s) below. After a regeneration a
/// recording can hold more than one transcript; each version is then shown in
/// its own labeled block with per-version copy and remove. Chrome-less — the
/// enclosing `RecordingsList` draws the grouped card and the hairline separators
/// between rows. Shared by the History pane (all recordings) and the
/// Conversations pane (conversations only).
struct RecordingRow: View {
    let entry: RecordingHistoryEntry
    let isPlaying: Bool
    /// Hidden in the Conversations list, where every row is the same type.
    var showsTypeBadge: Bool = true
    let onPlay: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    /// Removes one transcript version (by variant id) from this recording.
    let onRemoveTranscript: (UUID) -> Void
    /// Persists the canonical-label → name mapping for this recording.
    let onRenameSpeakers: ([String: String]) -> Void

    @Bindable private var regenerator = TranscriptRegenerator.shared
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var showRegenerateMenu = false
    @State private var showRenameSpeakers = false
    /// Draft names shown in the rename popover, seeded from the entry on open and
    /// committed to the store when the popover closes.
    @State private var speakerNameDrafts: [String: String] = [:]
    /// Row action icons stay hidden until the pointer is over the row — the list
    /// reads calm at rest and reveals its controls on demand.
    @State private var isHovering = false

    private var isRegenerating: Bool { regenerator.activeID == entry.id }

    /// Canonical speaker labels present in the stored transcript. The rename
    /// control only appears when this is non-empty (i.e. a diarized recording).
    private var speakerLabels: [String] { SpeakerRelabeler.speakerLabels(in: entry.transcript) }

    /// Applies the entry's speaker-name mapping to any transcript variant for
    /// display and copy — the stored string keeps its canonical "Speaker N" labels.
    private func displayText(_ text: String) -> String {
        SpeakerRelabeler.apply(names: entry.speakerNames ?? [:], to: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                PlayTile(isPlaying: isPlaying, action: onPlay)

                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.dateFormatter.string(from: entry.createdAt))
                        .font(.system(size: 13, weight: .medium))
                    HStack(spacing: 5) {
                        if showsTypeBadge {
                            RecordingTypeBadge(source: entry.source)
                            Text("·")
                                .font(.system(size: 11))
                                .foregroundStyle(.quaternary)
                        }
                        Text(metaLine)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 12)

                actionButtons
            }

            transcriptSection

            if let failure = regenerator.failure, failure.id == entry.id {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(failure.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Dismiss") { regenerator.dismissFailure() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
        .onDisappear { copyResetTask?.cancel() }
    }

    /// Favorite / regenerate / copy / delete. Quiet by default: only the star
    /// shows when a recording is favorited; the full set appears on hover (and
    /// the regenerate spinner stays put while a regeneration is in flight).
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 2) {
            if entry.isFavorited || isHovering {
                iconButton(
                    systemName: entry.isFavorited ? "star.fill" : "star",
                    help: entry.isFavorited ? "Remove from Favorites" : "Add to Favorites",
                    tint: entry.isFavorited ? .yellow : .secondary,
                    action: onToggleFavorite
                )
            }
            // Popover-open states keep the anchor buttons mounted after the
            // pointer leaves the row — an anchor that unmounts (hover ends when
            // the cursor enters the popover) tears its popover down with it.
            if isHovering || isRegenerating || showRenameSpeakers || showRegenerateMenu {
                if !speakerLabels.isEmpty {
                    renameSpeakersControl
                }
                regenerateControl
                iconButton(
                    systemName: copied ? "checkmark" : "doc.on.doc",
                    help: "Copy transcript",
                    tint: copied ? .green : .secondary,
                    action: copyActiveTranscript
                )
                iconButton(
                    systemName: "trash",
                    help: "Delete recording",
                    tint: .secondary,
                    action: onDelete
                )
            }
        }
    }

    /// One plain transcript, or — when the recording has alternate versions — a
    /// labeled, removable block per version (newest/active first).
    @ViewBuilder
    private var transcriptSection: some View {
        if entry.hasAlternateTranscripts {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entry.transcriptVariants) { variant in
                    TranscriptBlockView(
                        text: displayText(variant.text),
                        header: TranscriptBlockView.Header(
                            label: modelLabel(for: variant),
                            isActive: variant.id == entry.id,
                            onRemove: { onRemoveTranscript(variant.id) }
                        )
                    )
                }
            }
        } else {
            TranscriptBlockView(text: displayText(entry.transcript), header: nil)
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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
    private var speakerNamePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name speakers")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(speakerLabels, id: \.self) { label in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField(label, text: speakerNameBinding(for: label))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { showRenameSpeakers = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tint)
            }
        }
        .padding(14)
        .frame(width: 220)
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
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                if regenerator.totalChunks > 1 {
                    Text("\(regenerator.transcribedChunks)/\(regenerator.totalChunks)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minWidth: 24, minHeight: 24)
            .help("Regenerating transcript…")
        } else {
            Button {
                showRegenerateMenu.toggle()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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

    private func iconButton(
        systemName: String,
        help: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

/// Renders one transcript: a selectable, expandable body that clamps to a few
/// lines with "Show more". With a `header` (used when a recording has more than
/// one version) it draws a labeled, lightly-tinted card with per-version copy
/// and remove; without one it's the bare text, as a single-transcript row shows.
struct TranscriptBlockView: View {
    let text: String
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

    /// Lines shown before the transcript is clamped and a "Show more" appears.
    /// Kept short so a collapsed row scans as a preview, not a wall of text.
    private static let collapsedLineLimit = 3

    /// One source of truth for the transcript type, shared by the visible body
    /// and the hidden measuring probes so truncation is measured against exactly
    /// what's drawn.
    private static let transcriptFont = Font.system(size: 12)

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
            VStack(alignment: .leading, spacing: 8) {
                headerRow(header)
                transcriptBody
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(header.isActive ? Color.accentColor.opacity(0.35) : Color.clear)
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                transcriptBody
            }
        }
    }

    private func headerRow(_ header: Header) -> some View {
        HStack(spacing: 8) {
            if header.isActive {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
            }
            Text(header.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(header.isActive ? .primary : .secondary)
            if header.isActive {
                Text("Current")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
            Spacer(minLength: 8)
            smallIcon(copied ? "checkmark" : "doc.on.doc", tint: copied ? .green : .secondary, help: "Copy this version") {
                copyText()
            }
            smallIcon("trash", tint: .secondary, help: "Remove this version", action: header.onRemove)
        }
    }

    @ViewBuilder
    private var transcriptBody: some View {
        Text(text)
            .font(Self.transcriptFont)
            .foregroundStyle(.secondary)
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
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tint)
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
            .font(Self.transcriptFont)
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
                .font(.system(size: 11))
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

    var body: some View {
        let resolved = source ?? .dictation
        HStack(spacing: 3) {
            Image(systemName: resolved.symbolName)
                .font(.system(size: 9, weight: .medium))
            Text(resolved.displayName)
                .font(.system(size: 11))
        }
        .foregroundStyle(.tertiary)
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
                    .fill(
                        isPlaying
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color.primary.opacity(0.06))
                    )
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isPlaying ? Color.white : Color.secondary)
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isPlaying ? "Stop" : "Play recording")
    }
}
