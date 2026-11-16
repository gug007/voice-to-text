import SwiftUI

// MARK: - The one detail-pane shell
//
// Every pane used to open its own `ScrollView`, pick its own margin (32 here,
// 36 there) and stretch its content to whatever width the window happened to
// be. `PaneScaffold` is the single shell they all share now:
//
//   • one ScrollView per pane, with the `.soft` top scroll-edge effect on
//     macOS 26+: content fades out under the toolbar instead of being cut
//     mid-glyph at a hard line. That effect is what makes the manual
//     `Divider()` under every header unnecessary.
//   • a 24pt (`Space.s7`) margin on all sides, replacing the old 32/36 mix.
//   • one 20pt (`Space.section`) gap between top-level groups.
//   • a 640pt max content column, left-aligned. Past ~688pt of pane width the
//     column stops growing and the surplus becomes right-hand gutter, so a
//     maximised window guttters instead of stretching a toggle row across a
//     27" display.
//
// At the 720pt minimum window width the sidebar takes 188–208, leaving ~512pt
// of pane — which is exactly why the column caps at 640 rather than higher.

/// ```swift
/// PaneScaffold {
///     PaneHeader(subtitle: "Keep VoiceToText up to date.")
///     SettingsGroup { … }
///     SettingsGroup("Release Notes") { … }
/// }
/// ```
struct PaneScaffold<Content: View>: View {
    /// Gap between top-level sections. One value for the whole app.
    var spacing: CGFloat = Space.section
    /// The reading column cap. Panes never override this; the parameter exists
    /// so the number has one name instead of eight literals.
    var maxContentWidth: CGFloat = 640
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: maxContentWidth, alignment: .leading)
            .padding(Space.s7)
            // Left-align the (capped) column inside a pane that may be much
            // wider than it.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .paneScrollEdge()
        .overlay { ToolbarFade() }
    }
}

/// The canvas under the (backing-less) toolbar plus a 20pt fade below it, so
/// content scrolling up dissolves under the pane title instead of being cut
/// at a hairline. Sits over the scroll view, which extends under the toolbar.
private struct ToolbarFade: View {
    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            VStack(spacing: 0) {
                Palette.canvas
                    .frame(height: max(0, top - 4))
                LinearGradient(
                    colors: [Palette.canvas, Palette.canvas.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: top > 0 ? 20 : 0)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The `.soft` top scroll-edge effect, gated. On macOS 15 the pane simply
    /// scrolls under a plain toolbar — no effect, but also no traffic-light
    /// collision, which is the part that actually mattered.
    ///
    /// One per scroll view: two nested scroll views both declaring an edge
    /// effect fight over the same edge.
    @ViewBuilder
    nonisolated func paneScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

// MARK: - Section header

/// A Title Case header (the `SettingsGroup` header style) over a stack of
/// plates. Prefer `SettingsGroup`, which puts the rows on one plate; this is
/// for groups whose children are separate plates.
struct PaneSection<Content: View>: View {
    let title: String
    /// Gap between the plates in this group.
    var spacing: CGFloat = Space.s5
    @ViewBuilder var content: Content

    init(_ title: String, spacing: CGFloat = Space.s5, @ViewBuilder content: () -> Content) {
        self.title = title
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FormMetrics.groupLabelGap) {
            SettingsGroupHeader(title)
                .padding(.horizontal, FormMetrics.rowHorizontalPadding)
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
    }
}

// MARK: - Pane swap

extension AnyTransition {
    /// The sidebar-driven pane swap: opacity 0→1 with a 4pt upward drift on the
    /// way in, a plain fade on the way out. Deliberately asymmetric — two panes
    /// sliding past each other reads as a bug, one arriving reads as a change.
    /// Driven by `Motion.layout`; the sidebar itself never cross-fades.
    static var paneSwap: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 4)),
            removal: .opacity
        )
    }
}
