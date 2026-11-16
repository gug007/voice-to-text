import SwiftUI

// MARK: - Grouped form
//
// One plate per section, not per setting. A `SettingsGroup` draws an optional
// header above the plate, its rows separated by 1px hairlines inset 16pt from
// the leading edge, and an optional footer below. Groups sit `Space.section`
// (20pt) apart, which `PaneScaffold` applies by default.

/// A titled section of rows on one plate.
///
/// Each direct child is a row; hairlines are inserted between them
/// automatically (an `if` that is false or an empty `ForEach` adds none).
/// Children supply their own padding: use `SettingsRow`, or put
/// `.settingsRowPadding()` on a custom row. Rows are laid out eagerly; a list
/// of hundreds (History) belongs in `FlushPlate`, which is lazy.
///
/// ```swift
/// SettingsGroup("App", footer: "Hidden from the Dock, VoiceToText stays in the menu bar.") {
///     SettingsRow("Launch at login", isOn: $launchAtLogin)
///     SettingsRow("Appearance", caption: appearanceCaption) {
///         Picker("Appearance", selection: $mode) { … }
///             .pickerStyle(.segmented)
///             .labelsHidden()
///     }
///     MyCustomRow().settingsRowPadding()
/// }
///
/// // A trailing accessory on the header line (a count, a small button):
/// SettingsGroup("Recordings") { rows } accessory: {
///     Text("12 · 3 MB").typo(.mono).foregroundStyle(.inkMuted)
/// }
/// ```
struct SettingsGroup<Content: View, Accessory: View>: View {
    var header: String?
    var footer: String?
    /// Leading inset of the hairline between rows. Rows with a leading icon
    /// pass the x of their title so the line starts under the text.
    var dividerInset: CGFloat = FormMetrics.rowHorizontalPadding
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    init(
        _ header: String? = nil,
        footer: String? = nil,
        dividerInset: CGFloat = FormMetrics.rowHorizontalPadding,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.header = header
        self.footer = footer
        self.dividerInset = dividerInset
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FormMetrics.groupLabelGap) {
            if header != nil || Accessory.self != EmptyView.self {
                HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                    if let header {
                        SettingsGroupHeader(header)
                    }
                    Spacer(minLength: 0)
                    accessory
                }
                .padding(.horizontal, FormMetrics.rowHorizontalPadding)
            }

            Plate(.flush) {
                VStack(alignment: .leading, spacing: 0) {
                    Group(subviews: content) { rows in
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                RowHairline(
                                    leadingInset: rows[index - 1].containerValues.settingsDividerInset ?? dividerInset
                                )
                            }
                            row
                        }
                    }
                }
            }

            if let footer {
                SettingsGroupFooter(footer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsGroup where Accessory == EmptyView {
    init(
        _ header: String? = nil,
        footer: String? = nil,
        dividerInset: CGFloat = FormMetrics.rowHorizontalPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.init(header, footer: footer, dividerInset: dividerInset, content: content) {
            EmptyView()
        }
    }
}

/// The header above a group: 13pt semibold, secondary ink, Title Case. Use it
/// on its own only when a header must sit over something that is not a
/// `SettingsGroup` (a list built elsewhere).
struct SettingsGroupHeader: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .typo(.headline)
            .foregroundStyle(Palette.inkMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The note under a group: 11pt secondary ink, wraps.
struct SettingsGroupFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .typo(.caption)
            .foregroundStyle(Palette.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, FormMetrics.rowHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The 1px separator between rows, inset from the leading edge.
struct RowHairline: View {
    var leadingInset: CGFloat = FormMetrics.rowHorizontalPadding
    @Environment(\.displayScale) private var displayScale
    @Environment(\.increaseContrast) private var increaseContrast

    var body: some View {
        Rectangle()
            .fill(increaseContrast ? Palette.hairlineContrast : Palette.divider)
            .frame(height: 1 / max(displayScale, 1))
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

extension ContainerValues {
    /// Set by `.settingsDividerInset(_:)`.
    @Entry var settingsDividerInset: CGFloat? = nil
}

extension View {
    /// Starts the hairline *below* this row at `inset` instead of the group's
    /// default — for a row with a leading icon, pass the x of its text.
    ///
    /// ```swift
    /// IconRow().settingsRowPadding().settingsDividerInset(68)
    /// ```
    func settingsDividerInset(_ inset: CGFloat) -> some View {
        containerValue(\.settingsDividerInset, inset)
    }
}

// MARK: - Row

/// The standard row of a `SettingsGroup`: title (13pt regular), optional
/// caption (11pt secondary — aim for one line), and a trailing control pinned
/// to the group's trailing edge at its ideal width. Min height 44pt, 12pt
/// vertical / 16pt horizontal padding.
///
/// Give the trailing control its own accessibility label — usually the row
/// title with `.labelsHidden()`.
///
/// ```swift
/// SettingsRow("Microphone", caption: "Used for dictation and conversations.") {
///     MicrophonePicker()
/// }
///
/// SettingsRow("Show in menu bar", caption: caption, isOn: $showsMenuBarIcon)
///
/// // Extra content under the title line, still inside the row (a preview,
/// // a progress bar, an inline warning):
/// SettingsRow("Recording HUD", caption: "Timer, meter and controls.") {
///     sizePicker
/// } below: {
///     HUDPreview()
/// }
/// ```
struct SettingsRow<Trailing: View, Below: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var below: Below

    init(
        _ title: String,
        caption: String? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder below: () -> Below
    ) {
        self.title = title
        self.caption = caption
        self.trailing = trailing()
        self.below = below()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(alignment: .center, spacing: Space.s6) {
                SettingsRowLabel(title: title, caption: caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
                    .fixedSize()
            }
            below
        }
        .settingsRowPadding()
        .accessibilityElement(children: .contain)
    }
}

extension SettingsRow where Below == EmptyView {
    init(_ title: String, caption: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, caption: caption, trailing: trailing) { EmptyView() }
    }
}

extension SettingsRow where Trailing == EmptyView, Below == EmptyView {
    /// A label-only row (no control).
    init(_ title: String, caption: String? = nil) {
        self.init(title, caption: caption, trailing: { EmptyView() }) { EmptyView() }
    }
}

extension SettingsRow where Below == EmptyView {
    /// A row whose control is a switch bound to `isOn`. The switch is labelled
    /// with the row title for VoiceOver.
    init(_ title: String, caption: String? = nil, isOn: Binding<Bool>) where Trailing == SettingsSwitch {
        self.init(title, caption: caption) { SettingsSwitch(title: title, isOn: isOn) }
    }
}

/// The switch `SettingsRow(_:caption:isOn:)` uses: a native `.switch`
/// toggle, label hidden but kept for accessibility.
struct SettingsSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

/// Title + optional caption, the leading half of a `SettingsRow`. Exposed for
/// custom rows that need the same typography next to a non-standard control.
struct SettingsRowLabel: View {
    let title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title)
                .typo(.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    /// The padding and minimum height of a `SettingsRow`, for a custom row
    /// placed directly in a `SettingsGroup`.
    func settingsRowPadding() -> some View {
        padding(.vertical, FormMetrics.rowVerticalPadding)
            .padding(.horizontal, FormMetrics.rowHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: FormMetrics.rowMinHeight, alignment: .leading)
    }
}

#if DEBUG
#Preview("SettingsGroup") {
    @Previewable @State var on = true
    @Previewable @State var mode = 0
    VStack(alignment: .leading, spacing: Space.section) {
        SettingsGroup("App", footer: "Hidden from the Dock, VoiceToText stays in the menu bar.") {
            SettingsRow("Launch at login", caption: "Starts in the background when you sign in.", isOn: $on)
            SettingsRow("Appearance") {
                Picker("Appearance", selection: $mode) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
    .padding(Space.s7)
    .frame(width: 560)
    .background(Palette.canvas)
    .motionEnvironment()
}
#endif
