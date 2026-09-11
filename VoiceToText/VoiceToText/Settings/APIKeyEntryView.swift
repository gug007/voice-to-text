import SwiftUI

/// Provider-agnostic verification outcome. Both engines keep their own
/// connection-test enums; the config factories below map onto this one so the
/// field never has to know which provider it is talking to.
nonisolated enum APIKeyVerification: Sendable {
    case ok
    case rejected
    case failed(String)
}

/// Everything `APIKeyEntryView` needs to serve one provider. Built by the two
/// factories below; no call site assembles one by hand.
struct APIKeyProviderConfig {
    let providerName: String
    /// Placeholder shown while no key is stored.
    let pastePrompt: String
    let getKeyURL: URL
    let looksLikeKey: (String) -> Bool
    let verify: @MainActor (String) async -> APIKeyVerification
    let verifyStored: @MainActor () async -> APIKeyVerification
    let save: @MainActor (String) -> Void
    let clear: @MainActor () -> Void
    let hasKey: @MainActor () -> Bool
    let keySuffix: @MainActor () -> String?
}

extension APIKeyProviderConfig {
    static var openAI: APIKeyProviderConfig {
        APIKeyProviderConfig(
            providerName: "OpenAI",
            pastePrompt: "Paste your OpenAI key (starts with sk-)",
            getKeyURL: OpenAIEndpoint.apiKeysDocs,
            looksLikeKey: OpenAIAPIKey.looksLikeKey,
            verify: { await APIKeyVerification(OpenAITranscriptionEngine.testConnection(apiKey: $0)) },
            verifyStored: { await APIKeyVerification(OpenAITranscriptionEngine.testConnection()) },
            save: { OpenAIAPIKeyStore.shared.setKey($0) },
            clear: { OpenAIAPIKeyStore.shared.clearKey() },
            hasKey: { OpenAIAPIKeyStore.shared.hasKey },
            keySuffix: { OpenAIAPIKeyStore.shared.keySuffix }
        )
    }

    static var elevenLabs: APIKeyProviderConfig {
        APIKeyProviderConfig(
            providerName: "ElevenLabs",
            pastePrompt: "Paste your ElevenLabs key",
            getKeyURL: URL(string: "https://elevenlabs.io/app/settings/api-keys")!,
            looksLikeKey: ElevenLabsAPIKey.looksLikeKey,
            verify: { await APIKeyVerification(ElevenLabsRealtimeEngine.testConnection(apiKey: $0)) },
            verifyStored: { await APIKeyVerification(ElevenLabsRealtimeEngine.testConnection()) },
            save: { ElevenLabsAPIKeyStore.shared.setKey($0) },
            clear: { ElevenLabsAPIKeyStore.shared.clearKey() },
            hasKey: { ElevenLabsAPIKeyStore.shared.hasKey },
            keySuffix: { ElevenLabsAPIKeyStore.shared.keySuffix }
        )
    }

    static func forProvider(_ provider: CloudProvider) -> APIKeyProviderConfig {
        switch provider {
        case .openAI: return .openAI
        case .elevenLabs: return .elevenLabs
        }
    }
}

extension APIKeyVerification {
    init(_ result: OpenAIConnectionTest) {
        switch result {
        case .ok: self = .ok
        case .rejected: self = .rejected
        case .failed(let message): self = .failed(message)
        }
    }

    init(_ result: ElevenLabsConnectionTest) {
        switch result {
        case .ok: self = .ok
        case .rejected: self = .rejected
        case .failed(let message): self = .failed(message)
        }
    }
}

/// Paste → verified → saved, in one step. The user copies a key on the
/// provider's site, comes back, and pastes: the paste itself triggers
/// verification, and a key the provider accepts is stored without a Save click.
///
/// The pasteboard is never read programmatically — macOS shows a privacy alert
/// for that — so there is no "Paste" button; the field is focused instead and
/// ⌘V does the work.
struct APIKeyEntryView: View {
    let config: APIKeyProviderConfig
    /// Test and Remove. On in the Cloud pane, off in the inline popovers,
    /// where the only job is getting a working key in.
    var showsManagementControls: Bool = false
    /// Whether this field grabs focus on appear when no key is stored. Off for
    /// the second provider in a pane, so the two don't fight over first responder.
    var autoFocusesField: Bool = true
    var onConnected: () -> Void = {}

    @State private var draft: String = ""
    @State private var status: Status?
    @State private var isConnecting = false
    @State private var isTesting = false
    /// The value the paste heuristic last fired on, so a rejected key isn't
    /// re-verified on every keystroke that follows.
    @State private var lastAutoTried: String?
    @FocusState private var isFieldFocused: Bool

    private enum StatusKind { case neutral, success, failure }

    private struct Status {
        let message: String
        let kind: StatusKind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            if !config.hasKey() {
                getKeyCallout
            }

            keyField

            controlRow

            if let status {
                Text(status.message)
                    .typo(.caption)
                    .foregroundStyle(color(for: status.kind))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            if config.hasKey() {
                quietGetKeyLink
            }
        }
        .defaultFocus($isFieldFocused, autoFocusesField && !config.hasKey())
        .onChange(of: draft) { old, new in
            handleDraftChange(from: old, to: new)
        }
        .onAppear {
            if autoFocusesField && !config.hasKey() {
                isFieldFocused = true
            }
        }
        .onDisappear {
            draft = ""
            status = nil
            lastAutoTried = nil
        }
    }

    // MARK: - Pieces

    private var getKeyCallout: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Link(destination: config.getKeyURL) {
                HStack(spacing: Space.s2) {
                    Text("Get an API key")
                    Image(systemName: "arrow.up.right")
                        .font(Typo.micro)
                }
                .typo(.captionMedium)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Text("Create a key on \(config.providerName), copy it, and paste it here. It's verified and saved automatically.")
                .typo(.caption)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keyField: some View {
        SecureField(
            "",
            text: $draft,
            prompt: Text(fieldPrompt).foregroundStyle(Palette.inkFaint)
        )
        .textFieldStyle(.plain)
        .font(Typo.mono)
        .focused($isFieldFocused)
        .padding(.horizontal, Space.s5)
        .padding(.vertical, Space.s5)
        .background {
            // Radius 10 = the plate's 16 minus this well's 6pt inset.
            ConcentricRectangle(inset: Space.s3) { shape in
                shape
                    .fill(Palette.wellFill)
                    .overlay(shape.strokeBorder(Palette.hairline))
            }
        }
        .onSubmit { Task { await connect() } }
    }

    @ViewBuilder
    private var controlRow: some View {
        HStack(spacing: Space.s5) {
            Button {
                Task { await connect() }
            } label: {
                if isConnecting {
                    HStack(spacing: Space.s3) {
                        ProgressView().controlSize(.small)
                        Text("Connecting…")
                    }
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(Palette.accent)
            .disabled(trimmedDraft.isEmpty || isBusy)

            if showsManagementControls && config.hasKey() {
                Button {
                    Task { await testStoredKey() }
                } label: {
                    if isTesting {
                        HStack(spacing: Space.s3) {
                            ProgressView().controlSize(.small)
                            Text("Testing…")
                        }
                    } else {
                        Text("Test")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isBusy)

                Spacer()

                // Destructive text button: quiet by default, signalLive on hover
                // — never a filled red control.
                Button {
                    removeKey()
                } label: {
                    Text("Remove")
                        .typo(.captionMedium)
                }
                .buttonStyle(DestructiveTextButtonStyle())
                .help("Forget the saved API key")
            } else {
                Spacer()
            }
        }
    }

    private var quietGetKeyLink: some View {
        Link(destination: config.getKeyURL) {
            HStack(spacing: Space.s2) {
                Text("Get an API key")
                Image(systemName: "arrow.up.right")
                    .font(Typo.micro)
            }
            .typo(.captionMedium)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accent)
    }

    // MARK: - State

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isBusy: Bool { isConnecting || isTesting }

    private var fieldPrompt: String {
        guard config.hasKey() else { return config.pastePrompt }
        if let suffix = config.keySuffix() {
            return "Replace key ending in …\(suffix)"
        }
        return "Replace existing key"
    }

    private func color(for kind: StatusKind) -> Color {
        switch kind {
        case .neutral: return Palette.inkMuted
        case .success: return Palette.signalReady
        case .failure: return Palette.signalWarn
        }
    }

    // MARK: - Actions

    private func handleDraftChange(from old: String, to new: String) {
        guard !isBusy else { return }
        guard Self.isLikelyPaste(from: old, to: new) else { return }
        let candidate = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.looksLikeKey(candidate), candidate != lastAutoTried else { return }
        lastAutoTried = candidate
        Task { await connect() }
    }

    /// A paste lands as one big jump or replaces the whole field; typing only
    /// ever appends or removes a character at the end.
    private nonisolated static func isLikelyPaste(from old: String, to new: String) -> Bool {
        if new.count - old.count > 4 { return true }
        guard new.count >= 20 else { return false }
        return !new.hasPrefix(old) && !old.hasPrefix(new)
    }

    private func connect() async {
        let candidate = trimmedDraft
        guard !candidate.isEmpty, !isBusy else { return }
        isConnecting = true
        defer { isConnecting = false }

        switch await config.verify(candidate) {
        case .ok:
            config.save(candidate)
            clearDraft()
            status = Status(message: connectedMessage(), kind: .success)
            onConnected()

        case .rejected:
            // Deliberately not saved: a key the provider refuses would only fail
            // again at the first dictation, far from the field that can fix it.
            status = Status(
                message: "\(config.providerName) rejected this key. Check it and try again.",
                kind: .failure
            )

        case .failed(let message):
            // Offline, or the provider is having a moment — neither is a reason
            // to make the user paste again later, so the key is stored anyway.
            config.save(candidate)
            clearDraft()
            status = Status(message: "Saved, but couldn't verify: \(message)", kind: .neutral)
            onConnected()
        }
    }

    private func testStoredKey() async {
        guard !isBusy else { return }
        isTesting = true
        defer { isTesting = false }

        switch await config.verifyStored() {
        case .ok:
            status = Status(message: connectedMessage(), kind: .success)
        case .rejected:
            status = Status(
                message: "\(config.providerName) rejected this key. Check it and try again.",
                kind: .failure
            )
        case .failed(let message):
            status = Status(message: "Couldn't verify: \(message)", kind: .neutral)
        }
    }

    private func removeKey() {
        config.clear()
        clearDraft()
        status = Status(message: "Key removed.", kind: .neutral)
        isFieldFocused = true
    }

    private func clearDraft() {
        draft = ""
        lastAutoTried = nil
    }

    private func connectedMessage() -> String {
        guard let suffix = config.keySuffix() else { return "Connected." }
        return "Connected — key ending in …\(suffix)"
    }
}
