import SwiftUI

/// Provider-agnostic verification outcome. The engines keep their own
/// connection-test enums; the config factories below map onto this one so the
/// field never has to know which provider it is talking to.
nonisolated enum APIKeyVerification: Sendable {
    case ok
    case rejected
    case failed(String)
}

/// Everything `APIKeyEntryView` needs to serve one provider. Built by the
/// factories below; no call site assembles one by hand.
struct APIKeyProviderConfig {
    let provider: CloudProvider
    let providerName: String
    /// Placeholder shown while no key is stored.
    let pastePrompt: String
    /// How the provider's keys start, when they have a fixed prefix.
    let keyPrefix: String?
    let getKeyURL: URL
    let looksLikeKey: (String) -> Bool
    let verify: @MainActor (String) async -> APIKeyVerification
    let verifyStored: @MainActor () async -> APIKeyVerification
    let save: @MainActor (String) -> Void
    /// The stored key itself, read only to hold it for a removal's Undo.
    let readKey: @MainActor () -> String?
    let clear: @MainActor () -> Void
    let hasKey: @MainActor () -> Bool
    let keySuffix: @MainActor () -> String?
}

extension APIKeyProviderConfig {
    static var openAI: APIKeyProviderConfig {
        APIKeyProviderConfig(
            provider: .openAI,
            providerName: "OpenAI",
            pastePrompt: "Paste your OpenAI key",
            keyPrefix: "sk-",
            getKeyURL: OpenAIEndpoint.apiKeysDocs,
            looksLikeKey: OpenAIAPIKey.looksLikeKey,
            verify: { await APIKeyVerification(OpenAITranscriptionEngine.testConnection(apiKey: $0)) },
            verifyStored: { await APIKeyVerification(OpenAITranscriptionEngine.testConnection()) },
            save: { OpenAIAPIKeyStore.shared.setKey($0) },
            readKey: { OpenAIAPIKey.read() },
            clear: { OpenAIAPIKeyStore.shared.clearKey() },
            hasKey: { OpenAIAPIKeyStore.shared.hasKey },
            keySuffix: { OpenAIAPIKeyStore.shared.keySuffix }
        )
    }

    static var elevenLabs: APIKeyProviderConfig {
        APIKeyProviderConfig(
            provider: .elevenLabs,
            providerName: "ElevenLabs",
            pastePrompt: "Paste your ElevenLabs key",
            keyPrefix: nil,
            getKeyURL: URL(string: "https://elevenlabs.io/app/settings/api-keys")!,
            looksLikeKey: ElevenLabsAPIKey.looksLikeKey,
            verify: { await APIKeyVerification(ElevenLabsRealtimeEngine.testConnection(apiKey: $0)) },
            verifyStored: { await APIKeyVerification(ElevenLabsRealtimeEngine.testConnection()) },
            save: { ElevenLabsAPIKeyStore.shared.setKey($0) },
            readKey: { ElevenLabsAPIKey.read() },
            clear: { ElevenLabsAPIKeyStore.shared.clearKey() },
            hasKey: { ElevenLabsAPIKeyStore.shared.hasKey },
            keySuffix: { ElevenLabsAPIKeyStore.shared.keySuffix }
        )
    }

    static var groq: APIKeyProviderConfig {
        APIKeyProviderConfig(
            provider: .groq,
            providerName: "Groq",
            pastePrompt: "Paste your Groq key",
            keyPrefix: "gsk_",
            getKeyURL: GroqEndpoint.apiKeysDocs,
            looksLikeKey: GroqAPIKey.looksLikeKey,
            verify: { await APIKeyVerification(OpenAITranscriptionEngine.testConnection(apiKey: $0, service: .groq)) },
            verifyStored: { await APIKeyVerification(OpenAITranscriptionEngine.testConnection(service: .groq)) },
            save: { GroqAPIKeyStore.shared.setKey($0) },
            readKey: { GroqAPIKey.read() },
            clear: { GroqAPIKeyStore.shared.clearKey() },
            hasKey: { GroqAPIKeyStore.shared.hasKey },
            keySuffix: { GroqAPIKeyStore.shared.keySuffix }
        )
    }

    static func forProvider(_ provider: CloudProvider) -> APIKeyProviderConfig {
        switch provider {
        case .openAI: return .openAI
        case .elevenLabs: return .elevenLabs
        case .groq: return .groq
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


/// One line of feedback under a key field or a provider row.
struct APIKeyStatusMessage: Equatable {
    enum Kind { case neutral, success, failure }

    let text: String
    let kind: Kind

    var color: Color {
        switch kind {
        case .neutral: return Palette.inkMuted
        case .success: return Palette.signalReady
        case .failure: return Palette.signalWarn
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
    /// Visible label above the field. Nil where the container already names
    /// it (the "OpenAI API key" popovers).
    var fieldLabel: String? = nil
    /// Whether this field grabs focus on appear when no key is stored. Off for
    /// the second provider in a pane, so the two don't fight over first responder.
    var autoFocusesField: Bool = true
    /// The provider's verdict on a key this field connected, so the Cloud row
    /// can keep showing it once the field goes away.
    var onVerified: ((APIKeyVerification) -> Void)? = nil
    /// Shows a Cancel button next to Connect (replacing a stored key).
    var onCancel: (() -> Void)? = nil
    /// Last on purpose: an unlabeled trailing closure lands here.
    var onConnected: () -> Void = {}

    @State private var draft: String = ""
    @State private var status: APIKeyStatusMessage?
    @State private var isConnecting = false
    /// The running verification, cancelled when the field goes away so a key
    /// the user backed out of is never saved.
    @State private var connectTask: Task<Void, Never>?
    /// The value the paste heuristic last fired on, so a rejected key isn't
    /// re-verified on every keystroke that follows.
    @State private var lastAutoTried: String?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let fieldLabel {
                Text(fieldLabel)
                    .typo(.captionMedium)
                    .foregroundStyle(Palette.inkMuted)
            }

            HStack(spacing: Space.s4) {
                keyField
                connectButton
                if let onCancel {
                    Button("Cancel") {
                        connectTask?.cancel()
                        onCancel()
                    }
                    .buttonTier(.secondary)
                }
            }

            // One line where it fits (the Cloud pane); the link drops under
            // the hint in the narrow popovers.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                    hintText
                    Spacer(minLength: Space.s4)
                    getKeyLink
                }
                VStack(alignment: .leading, spacing: 0) {
                    hintText
                    getKeyLink
                }
            }

            if let status {
                Text(status.text)
                    .typo(.caption)
                    .foregroundStyle(status.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .defaultFocus($isFieldFocused, autoFocusesField)
        .onChange(of: draft) { old, new in
            handleDraftChange(from: old, to: new)
        }
        .onAppear {
            if autoFocusesField {
                isFieldFocused = true
            }
        }
        .onDisappear {
            connectTask?.cancel()
            draft = ""
            status = nil
            lastAutoTried = nil
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var hintText: some View {
        if let hint {
            hint
                .typo(.caption)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var getKeyLink: some View {
        ExternalLink("Get an API key", destination: config.getKeyURL, font: Typo.caption)
    }

    private var keyField: some View {
        SecureField(
            "\(config.providerName) API key",
            text: $draft,
            prompt: Text(fieldPrompt).foregroundStyle(Palette.inkFaint)
        )
        .textFieldStyle(.plain)
        // SF Mono only for the typed key; the placeholder stays SF Pro.
        .font(draft.isEmpty ? Typo.body : Typo.code)
        .focused($isFieldFocused)
        // Esc cancels only from the focused field, so two open Replace
        // fields never compete for it. Without a Cancel, Esc is left alone
        // (it closes the key popovers).
        .onExitCommand(perform: onCancel.map { cancel in
            { () -> Void in
                connectTask?.cancel()
                cancel()
            }
        })
        .padding(.horizontal, Space.s4)
        .frame(height: FormMetrics.fieldHeight)
        .framedTextField(isFocused: isFieldFocused)
        .onSubmit { startConnect() }
    }

    private var connectButton: some View {
        Button {
            startConnect()
        } label: {
            if isConnecting {
                HStack(spacing: Space.s3) {
                    ProgressView().controlSize(.mini)
                    Text("Connecting…")
                }
            } else {
                Text("Connect")
            }
        }
        .buttonTier(.primary)
        .disabled(trimmedDraft.isEmpty || isConnecting)
        .help(trimmedDraft.isEmpty ? "Paste or type a key first" : "Check and save this key")
    }

    // MARK: - State

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var fieldPrompt: String {
        guard config.hasKey() else { return config.pastePrompt }
        if let suffix = config.keySuffix() {
            return "Paste a new key to replace …\(suffix)"
        }
        return "Paste a new key"
    }

    /// "Starts with gsk_", the prefix set as code and not followed by a
    /// full stop that would read as part of it.
    private var hint: Text? {
        config.keyPrefix.map { Text("Starts with ") + Text($0).font(Typo.code) }
    }

    private func report(_ message: APIKeyStatusMessage) {
        status = message
    }

    // MARK: - Actions

    private func handleDraftChange(from old: String, to new: String) {
        guard !isConnecting else { return }
        guard Self.isLikelyPaste(from: old, to: new) else { return }
        let candidate = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.looksLikeKey(candidate), candidate != lastAutoTried else { return }
        lastAutoTried = candidate
        startConnect()
    }

    /// A paste lands as one big jump or replaces the whole field; typing only
    /// ever appends or removes a character at the end.
    private nonisolated static func isLikelyPaste(from old: String, to new: String) -> Bool {
        if new.count - old.count > 4 { return true }
        guard new.count >= 20 else { return false }
        return !new.hasPrefix(old) && !old.hasPrefix(new)
    }

    /// One verification at a time: a paste and a Return (or two Returns)
    /// must not start a second one that Cancel can't reach.
    private func startConnect() {
        let candidate = trimmedDraft
        guard !candidate.isEmpty, !isConnecting else { return }
        isConnecting = true
        connectTask = Task { await connect(candidate) }
    }

    private func connect(_ candidate: String) async {
        defer { isConnecting = false }

        let verdict = await config.verify(candidate)
        // Cancelled or gone while the provider answered: save nothing.
        guard !Task.isCancelled else { return }
        switch verdict {
        case .ok:
            config.save(candidate)
            clearDraft()
            report(APIKeyStatusMessage(text: Self.connectedMessage(config), kind: .success))
            onVerified?(verdict)
            onConnected()

        case .rejected:
            // Deliberately not saved: a key the provider refuses would only fail
            // again at the first dictation, far from the field that can fix it.
            report(APIKeyStatusMessage(
                text: "\(config.providerName) rejected this key. Check it and try again.",
                kind: .failure
            ))

        case .failed(let message):
            // Offline, or the provider is having a moment — neither is a reason
            // to make the user paste again later, so the key is stored anyway.
            config.save(candidate)
            clearDraft()
            report(APIKeyStatusMessage(text: "Saved, but couldn't verify: \(message)", kind: .neutral))
            onVerified?(verdict)
            onConnected()
        }
    }

    private func clearDraft() {
        draft = ""
        lastAutoTried = nil
    }

    static func connectedMessage(_ config: APIKeyProviderConfig) -> String {
        guard let suffix = config.keySuffix() else { return "Connected." }
        return "Connected — key ending in …\(suffix)"
    }
}
