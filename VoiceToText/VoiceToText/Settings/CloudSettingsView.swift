import SwiftUI

struct CloudPane: View {
    @Bindable private var keyStore = OpenAIAPIKeyStore.shared
    @State private var draftKey: String = ""
    @State private var statusMessage: String?
    @State private var statusKind: StatusKind = .neutral
    @State private var isTesting: Bool = false

    @Bindable private var elevenKeyStore = ElevenLabsAPIKeyStore.shared
    @State private var draftElevenKey: String = ""
    @State private var elevenStatusMessage: String?
    @State private var elevenStatusKind: StatusKind = .neutral
    @State private var elevenIsTesting: Bool = false

    private static let elevenLabsKeysURL = URL(string: "https://elevenlabs.io/app/settings/api-keys")!

    /// The two provider tints, as light/dark pairs — raw `.blue` / `.purple`
    /// are not tokens and read differently in each appearance.
    private static let openAITint = Palette.accent
    private static let elevenLabsTint = Palette.dynamic(
        "providerElevenLabs", light: 0x5856D6, dark: 0x7D7AFF
    )

    private enum StatusKind { case neutral, success, failure }

    var body: some View {
        PaneScaffold {
            PaneHeader(
                title: "Cloud",
                subtitle: "Connect to online transcription. Your key stays on this Mac."
            )

            openAISection

            elevenLabsSection

            privacyFooter
        }
        .onAppear {
            draftKey = ""
            statusMessage = nil
            statusKind = .neutral
            draftElevenKey = ""
            elevenStatusMessage = nil
            elevenStatusKind = .neutral
        }
    }

    // MARK: - OpenAI section

    @ViewBuilder
    private var openAISection: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s6) {
                HStack(alignment: .center, spacing: Space.s5) {
                    ProviderIconTile(symbol: "cloud.fill", tint: Self.openAITint)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("OpenAI")
                            .typo(.title)
                            .foregroundStyle(Palette.ink)
                        Text("GPT Realtime Whisper, GPT-4o Transcribe, Whisper-1")
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Spacer(minLength: Space.s5)
                    StatusLabel(
                        level: keyStore.hasKey ? .ready : .warning,
                        text: keyStore.hasKey ? "Configured" : "Not set"
                    )
                }

                keyField

                actionRow

                if let statusMessage {
                    Text(statusMessage)
                        .typo(.caption)
                        .foregroundStyle(statusColor)
                        .transition(.opacity)
                }

                Link(destination: OpenAIEndpoint.apiKeysDocs) {
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
        }
    }

    private var keyField: some View {
        SecureField(
            "",
            text: $draftKey,
            prompt: Text(keyStore.hasKey ? "Replace existing key" : "Paste your API key")
                .foregroundStyle(Palette.inkFaint)
        )
        .textFieldStyle(.plain)
        .font(Typo.mono)
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
        .onSubmit { save() }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: Space.s5) {
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(Palette.accent)
                .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                Task { await testConnection() }
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
            .disabled(!keyStore.hasKey || isTesting)

            Spacer()

            if keyStore.hasKey {
                // Destructive text button: quiet by default, signalLive on hover
                // — never a filled red control.
                Button {
                    keyStore.clearKey()
                    draftKey = ""
                    setStatus("Key removed.", kind: .neutral)
                } label: {
                    Text("Remove")
                        .typo(.captionMedium)
                }
                .buttonStyle(DestructiveTextButtonStyle())
                .help("Forget the saved API key")
            }
        }
    }

    // MARK: - ElevenLabs section

    @ViewBuilder
    private var elevenLabsSection: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s6) {
                HStack(alignment: .center, spacing: Space.s5) {
                    ProviderIconTile(symbol: "waveform", tint: Self.elevenLabsTint)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("ElevenLabs")
                            .typo(.title)
                            .foregroundStyle(Palette.ink)
                        Text("Scribe v2 Realtime — live streaming transcription")
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Spacer(minLength: Space.s5)
                    StatusLabel(
                        level: elevenKeyStore.hasKey ? .ready : .warning,
                        text: elevenKeyStore.hasKey ? "Configured" : "Not set"
                    )
                }

                SecureField(
                    "",
                    text: $draftElevenKey,
                    prompt: Text(elevenKeyStore.hasKey ? "Replace existing key" : "Paste your API key")
                        .foregroundStyle(Palette.inkFaint)
                )
                .textFieldStyle(.plain)
                .font(Typo.mono)
                .padding(.horizontal, Space.s5)
                .padding(.vertical, Space.s5)
                .background {
                    ConcentricRectangle(inset: Space.s3) { shape in
                        shape
                            .fill(Palette.wellFill)
                            .overlay(shape.strokeBorder(Palette.hairline))
                    }
                }
                .onSubmit { saveEleven() }

                HStack(spacing: Space.s5) {
                    Button("Save") { saveEleven() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .tint(Palette.accent)
                        .disabled(draftElevenKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        Task { await testElevenConnection() }
                    } label: {
                        if elevenIsTesting {
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
                    .disabled(!elevenKeyStore.hasKey || elevenIsTesting)

                    Spacer()

                    if elevenKeyStore.hasKey {
                        Button {
                            elevenKeyStore.clearKey()
                            draftElevenKey = ""
                            setElevenStatus("Key removed.", kind: .neutral)
                        } label: {
                            Text("Remove")
                                .typo(.captionMedium)
                        }
                        .buttonStyle(DestructiveTextButtonStyle())
                        .help("Forget the saved API key")
                    }
                }

                if let elevenStatusMessage {
                    Text(elevenStatusMessage)
                        .typo(.caption)
                        .foregroundStyle(elevenStatusColor)
                        .transition(.opacity)
                }

                Link(destination: Self.elevenLabsKeysURL) {
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
        }
    }

    private var elevenStatusColor: Color {
        switch elevenStatusKind {
        case .neutral: return Palette.inkMuted
        case .success: return Palette.signalReady
        case .failure: return Palette.signalWarn
        }
    }

    private func setElevenStatus(_ message: String, kind: StatusKind) {
        elevenStatusMessage = message
        elevenStatusKind = kind
    }

    private func saveEleven() {
        let trimmed = draftElevenKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        elevenKeyStore.setKey(trimmed)
        draftElevenKey = ""
        setElevenStatus("Key saved.", kind: .success)
    }

    private func testElevenConnection() async {
        elevenIsTesting = true
        defer { elevenIsTesting = false }
        switch await ElevenLabsRealtimeEngine.testConnection() {
        case .ok:
            setElevenStatus("Connection OK — key works.", kind: .success)
        case .rejected:
            setElevenStatus("Key was rejected by ElevenLabs.", kind: .failure)
        case .failed(let message):
            setElevenStatus(message, kind: .failure)
        }
    }

    // MARK: - Privacy footer

    private var privacyFooter: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            Image(systemName: "lock.shield")
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.inkFaint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Privacy")
                    .typo(.captionMedium)
                    .foregroundStyle(Palette.inkMuted)
                Text("Cloud models upload your audio to the provider. Local models keep audio on this Mac.")
                    .typo(.caption)
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch statusKind {
        case .neutral: return Palette.inkMuted
        case .success: return Palette.signalReady
        case .failure: return Palette.signalWarn
        }
    }

    private func setStatus(_ message: String, kind: StatusKind) {
        statusMessage = message
        statusKind = kind
    }

    private func save() {
        let trimmed = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keyStore.setKey(trimmed)
        draftKey = ""
        setStatus("Key saved.", kind: .success)
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        switch await OpenAITranscriptionEngine.testConnection() {
        case .ok:
            setStatus("Connection OK — key works.", kind: .success)
        case .rejected:
            setStatus("Key was rejected by OpenAI.", kind: .failure)
        case .failed(let message):
            setStatus(message, kind: .failure)
        }
    }
}
