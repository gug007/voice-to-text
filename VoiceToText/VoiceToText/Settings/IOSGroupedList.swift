import SwiftUI

/// iOS-style building blocks for the History and Conversations panes: a bold
/// large title, inset-grouped cards, section captions/footers, capsule buttons,
/// and a hairline-separated list of recordings. These two screens read as the
/// app's "library" (browsing saved content) versus the utilitarian Settings
/// panes, so they lean on the iOS grouped-list visual language.

// MARK: - Header

/// Large navigation-style title + subtitle, bolder and bigger than `PaneHeader`
/// to anchor the inset-grouped layout the way an iOS large title does.
struct LargeTitleHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Grouped containers

/// A single rounded, inset card — the iOS "grouped section" surface. Holds one
/// control (a toggle row, the record card) or, with `RecordingsList`, a stack of
/// hairline-separated rows. Content manages its own padding so a list of rows
/// can run edge-to-edge with separators between them.
struct InsetCard<Content: View>: View {
    private static var cornerRadius: CGFloat { 16 }
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }
}

/// Small gray caption above a grouped section (an iOS list header). The
/// optional trailing slot carries section controls like "Clear All" or a
/// disk-usage figure.
struct GroupCaption<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 6)
    }
}

extension GroupCaption where Trailing == EmptyView {
    init(_ text: String) {
        self.init(text: text) { EmptyView() }
    }
}

/// Small gray explanatory text below a grouped section (an iOS list footer).
struct GroupFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
    }
}

// MARK: - Recordings list

/// An inset-grouped list of saved recordings: one card, rows divided by
/// edge-to-edge hairlines. Shared by History (all recordings, with type badges)
/// and Conversations (conversations only, badge hidden).
struct RecordingsList: View {
    let entries: [RecordingHistoryEntry]
    var showsTypeBadge: Bool = true
    let isPlaying: (RecordingHistoryEntry) -> Bool
    let onPlay: (RecordingHistoryEntry) -> Void
    let onDelete: (RecordingHistoryEntry) -> Void

    var body: some View {
        InsetCard {
            // Lazy so opening a long History doesn't lay out every row's
            // transcript and its two hidden measuring probes up front; only
            // rows scrolled into view are measured.
            LazyVStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1)
                    }
                    RecordingRow(
                        entry: entry,
                        isPlaying: isPlaying(entry),
                        showsTypeBadge: showsTypeBadge,
                        onPlay: { onPlay(entry) },
                        onDelete: { onDelete(entry) }
                    )
                }
            }
        }
    }
}

// MARK: - Capsule buttons

/// Filled or tinted capsule button in the iOS style — the primary affordance on
/// the Conversations record card (Start, Stop & Transcribe, Cancel).
struct CapsuleActionButton: View {
    enum Style { case primary, secondary }

    let title: String
    var systemImage: String? = nil
    var style: Style = .primary
    var tint: Color = .accentColor
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(style == .primary ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
            .background(
                Capsule()
                    .fill(style == .primary
                          ? AnyShapeStyle(tint)
                          : AnyShapeStyle(tint.opacity(0.14)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}
