import AppKit
import SwiftUI

/// A single saved-recording row: leading play tile, timestamp + metadata, copy
/// and delete controls, and the transcript below (selectable, expandable).
/// Chrome-less — the enclosing `RecordingsList` draws the grouped card and the
/// hairline separators between rows. Shared by the History pane (all recordings)
/// and the Conversations pane (conversations only).
struct RecordingRow: View {
    let entry: RecordingHistoryEntry
    let isPlaying: Bool
    /// Hidden in the Conversations list, where every row is the same type.
    var showsTypeBadge: Bool = true
    let onPlay: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void

    @Bindable private var regenerator = TranscriptRegenerator.shared
    @State private var overflowHeight: CGFloat = 0
    @State private var clampedHeight: CGFloat = 0
    @State private var expanded = false
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    private var isRegenerating: Bool { regenerator.activeID == entry.id }

    /// Lines shown before the transcript is clamped and a "Show more" appears.
    private static let collapsedLineLimit = 4

    /// Truncated when one extra line would make the transcript taller — i.e. it
    /// overflows the collapsed clamp. Derived from stable, expand-independent
    /// measurements (below), so toggling "Show more" never re-measures and
    /// flickers the layout.
    private var isTruncated: Bool { overflowHeight > clampedHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                PlayTile(isPlaying: isPlaying, action: onPlay)

                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.dateFormatter.string(from: entry.createdAt))
                        .font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 6) {
                        if showsTypeBadge {
                            RecordingTypeBadge(source: entry.source)
                        }
                        Text(metaLine)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 12)

                iconButton(
                    systemName: entry.isFavorited ? "star.fill" : "star",
                    help: entry.isFavorited ? "Remove from Favorites" : "Add to Favorites",
                    tint: entry.isFavorited ? .yellow : .secondary,
                    action: onToggleFavorite
                )
                regenerateControl
                iconButton(
                    systemName: copied ? "checkmark" : "doc.on.doc",
                    help: "Copy transcript",
                    tint: copied ? .green : .secondary,
                    action: copyTranscript
                )
                iconButton(
                    systemName: "trash",
                    help: "Delete recording",
                    tint: .secondary,
                    action: onDelete
                )
            }

            Text(entry.transcript)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.9))
                .textSelection(.enabled)
                .lineLimit(expanded ? nil : Self.collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                // A selectable Text on macOS paints its full content height
                // when clicked, even while layout still reserves only the
                // line-limit clamp — without this it spills over "Show more"
                // and the footer. Clip it to its laid-out bounds; expanded
                // (line-limit nil) makes the frame full height, so this is a
                // no-op there.
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
        .onDisappear { copyResetTask?.cancel() }
    }

    private var metaLine: String {
        var parts = [entry.durationSeconds.formattedClock]
        if let model = entry.modelName ?? entry.modelId, !model.isEmpty {
            parts.append(model)
        }
        return parts.joined(separator: " · ")
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
        Text(entry.transcript)
            .font(.system(size: 13))
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

    private func copyTranscript() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.transcript, forType: .string)
        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
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
            Menu {
                Section("Regenerate with") {
                    ForEach(ModelCatalog.all) { model in
                        Button {
                            Task { await regenerator.regenerate(entry: entry, modelId: model.id) }
                        } label: {
                            if model.id == entry.modelId {
                                Label(model.displayName, systemImage: "checkmark")
                            } else {
                                Text(model.displayName)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(regenerator.isRunning)
            .help("Regenerate transcript with another model")
        }
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

/// Small chip marking how a recording was made — "Dictation" (hotkey flow) or
/// "Conversation" (long mic+system capture). Accent-tinted for conversations,
/// neutral otherwise.
struct RecordingTypeBadge: View {
    let source: RecordingHistoryEntry.Source?

    var body: some View {
        let resolved = source ?? .dictation
        let isConversation = (resolved == .meeting)
        HStack(spacing: 3) {
            Image(systemName: resolved.symbolName)
                .font(.system(size: 8.5, weight: .semibold))
            Text(resolved.displayName)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(isConversation ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isConversation ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.08))
        )
    }
}

/// 36-pt circular play/stop control — the iOS media affordance. Filled accent
/// while playing, a soft accent wash at rest.
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
                        : AnyShapeStyle(Color.accentColor.opacity(0.14))
                    )
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isPlaying ? Color.white : Color.accentColor)
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isPlaying ? "Stop" : "Play recording")
    }
}
