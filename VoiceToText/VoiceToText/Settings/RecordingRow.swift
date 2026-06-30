import AppKit
import SwiftUI

/// A single saved-recording row: leading play tile, timestamp + metadata, copy
/// and delete controls, and the transcript below (selectable, expandable).
/// Shared by the History pane (all recordings) and the Conversations pane
/// (conversations only).
struct RecordingRow: View {
    let entry: RecordingHistoryEntry
    let isPlaying: Bool
    /// Hidden in the Conversations list, where every row is the same type.
    var showsTypeBadge: Bool = true
    let onPlay: () -> Void
    let onDelete: () -> Void

    @State private var overflowHeight: CGFloat = 0
    @State private var clampedHeight: CGFloat = 0
    @State private var expanded = false
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    /// Lines shown before the transcript is clamped and a "Show more" appears.
    private static let collapsedLineLimit = 4

    /// Truncated when one extra line would make the transcript taller — i.e. it
    /// overflows the collapsed clamp. Derived from stable, expand-independent
    /// measurements (below), so toggling "Show more" never re-measures and
    /// flickers the layout.
    private var isTruncated: Bool { overflowHeight > clampedHeight + 1 }

    var body: some View {
        RowCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    PlayTile(isPlaying: isPlaying, action: onPlay)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.dateFormatter.string(from: entry.createdAt))
                            .font(.system(size: 13, weight: .medium))
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
            .padding(16)
        }
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

/// 34×34 rounded play/stop control, styled like `ProviderIconTile` so rows
/// share the app's visual rhythm. Filled accent while playing.
struct PlayTile: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isPlaying
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(LinearGradient(
                            colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    )
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isPlaying ? Color.white : Color.accentColor)
            }
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isPlaying ? "Stop" : "Play recording")
    }
}
