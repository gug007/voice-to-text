import SwiftUI

// MARK: - Model naming

extension ModelDescriptor {
    /// "OpenAI", "Groq", or "On this Mac".
    var sourceName: String {
        backend.cloudProvider?.displayName ?? "On this Mac"
    }

    /// "GPT Transcribe · OpenAI", "Parakeet TDT v3 · On this Mac" — the one
    /// way to name a model outside its own provider section.
    var nameWithSource: String {
        "\(sectionedDisplayName) · \(sourceName)"
    }

    /// `cloud` for a cloud model, `laptopcomputer` for one on this Mac.
    var sourceSymbol: String {
        isCloud ? "cloud" : "laptopcomputer"
    }
}

// MARK: - Active model menu

/// A pull-down that switches the dictation model: the models that can run now
/// (`ModelSwitchPolicy.isUsable`), grouped "On this Mac" / per provider, a
/// checkmark on the active one, and "All Models…" to open the Models pane.
/// Picking a model calls `ModelRegistry.setActive`, the same call as the
/// Models pane and the menu-bar Model submenu; picks follow
/// `ModelSwitchPolicy.canChangeDictationModel`.
///
/// ```swift
/// ActiveModelMenu()                         // ☁ GPT Transcribe · OpenAI ⌄
/// ActiveModelMenu { MyCustomLabel() }       // any label; style it with .buttonStyle
/// Menu("Model") { ActiveModelMenuItems() }  // just the items, inside another menu
/// ```
struct ActiveModelMenu<Label: View>: View {
    @ViewBuilder var label: Label
    /// A disabled first line naming what the menu sets ("Dictation model").
    var menuTitle: String?
    /// Set by the label-less init: the built-in label gets the inline style.
    private var usesInlineStyle = false

    init(menuTitle: String? = nil, @ViewBuilder label: () -> Label) {
        self.menuTitle = menuTitle
        self.label = label()
    }

    var body: some View {
        let menu = Menu {
            ActiveModelMenuItems(title: menuTitle)
        } label: {
            label
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .accessibilityHint("Chooses the dictation model")

        if usesInlineStyle {
            menu
                .buttonStyle(InlineMenuButtonStyle())
                .fixedSize()
                .help("Dictation model. Click to change.")
        } else {
            menu
        }
    }
}

extension ActiveModelMenu where Label == ActiveModelLabel {
    /// The compact form: source glyph, "Name · Provider", chevron.
    init() {
        self.init { ActiveModelLabel() }
        usesInlineStyle = true
    }
}

/// The items of `ActiveModelMenu`, for embedding in another menu.
struct ActiveModelMenuItems: View {
    /// A disabled first line naming what the menu sets.
    var title: String? = nil

    private var registry: ModelRegistry { .shared }

    var body: some View {
        if let title {
            Text(title)
            Divider()
        }
        let canChange = ModelSwitchPolicy.canChangeDictationModel
        let ready = ModelCatalog.all.filter {
            $0.id == registry.activeModelId || ModelSwitchPolicy.isUsable($0, registry: registry)
        }
        ForEach(ModelGroup.sections(of: ready), id: \.group.id) { section in
            Section(section.group.title) {
                ForEach(section.models) { model in
                    Toggle(isOn: Binding(
                        get: { registry.activeModelId == model.id },
                        set: { if $0 { registry.setActive(model.id) } }
                    )) {
                        Text(model.sectionedDisplayName)
                    }
                    .disabled(!canChange)
                }
            }
        }
        if ready.isEmpty {
            Text("No models ready yet")
        }
        Divider()
        Button("All Models…") {
            WindowOpener.shared.showMain(section: .models)
        }
    }
}

/// Source glyph + "Name · Provider" (+ chevron) for the active dictation model.
struct ActiveModelLabel: View {
    var font: Font = Typo.caption
    var showsChevron = true
    private var registry: ModelRegistry { .shared }

    var body: some View {
        HStack(spacing: Space.s2) {
            if let model = registry.activeModel {
                Image(systemName: model.sourceSymbol)
                    .font(.system(size: 10, weight: .medium))
                    .accessibilityHidden(true)
                Text(model.nameWithSource)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("Choose a model")
            }
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                    .accessibilityHidden(true)
            }
        }
        .font(font)
        .foregroundStyle(Palette.inkMuted)
    }
}

/// A borderless inline menu trigger: content as given, a soft fill on hover.
struct InlineMenuButtonStyle: ButtonStyle {
    @Environment(\.motion) private var motion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.minimum, style: .continuous)
        configuration.label
            .padding(.horizontal, Space.s2)
            .padding(.vertical, Space.s1)
            .background(shape.fill(configuration.isPressed
                ? Palette.ink.opacity(0.12)
                : (isHovering ? Palette.wellFill : .clear)))
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(motion.hover, value: isHovering)
    }
}
