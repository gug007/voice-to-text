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

    private enum StatusKind { case neutral, success, failure }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                PaneHeader(
                    title: "Cloud",
                    subtitle: "Connect to online transcription. Your key stays on this Mac."
                )

                openAISection

                elevenLabsSection

                privacyFooter
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 36)
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 14) {
                ProviderIconTile(symbol: "cloud.fill", tint: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenAI")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Whisper-1, GPT-4o Transcribe, GPT-4o Mini Transcribe")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                StatusDot(
                    color: keyStore.hasKey ? .green : .orange,
                    label: keyStore.hasKey ? "Configured" : "Not set"
                )
            }

            keyField

            actionRow

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor)
                    .transition(.opacity)
            }

            Link(destination: OpenAIEndpoint.apiKeysDocs) {
                HStack(spacing: 4) {
                    Text("Get an API key")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private var keyField: some View {
        SecureField(
            "",
            text: $draftKey,
            prompt: Text(keyStore.hasKey ? "Replace existing key" : "Paste your API key")
                .foregroundStyle(.tertiary)
        )
        .textFieldStyle(.plain)
        .font(.system(size: 13, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .onSubmit { save() }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 10) {
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                Task { await testConnection() }
            } label: {
                if isTesting {
                    HStack(spacing: 6) {
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
                Button {
                    keyStore.clearKey()
                    draftKey = ""
                    setStatus("Key removed.", kind: .neutral)
                } label: {
                    Text("Remove")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Forget the saved API key")
            }
        }
    }

    // MARK: - ElevenLabs section

    @ViewBuilder
    private var elevenLabsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 14) {
                ProviderIconTile(symbol: "waveform", tint: .purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ElevenLabs")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Scribe v2 Realtime — live streaming transcription")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                StatusDot(
                    color: elevenKeyStore.hasKey ? .green : .orange,
                    label: elevenKeyStore.hasKey ? "Configured" : "Not set"
                )
            }

            SecureField(
                "",
                text: $draftElevenKey,
                prompt: Text(elevenKeyStore.hasKey ? "Replace existing key" : "Paste your API key")
                    .foregroundStyle(.tertiary)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .onSubmit { saveEleven() }

            HStack(spacing: 10) {
                Button("Save") { saveEleven() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(draftElevenKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    Task { await testElevenConnection() }
                } label: {
                    if elevenIsTesting {
                        HStack(spacing: 6) {
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
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("Forget the saved API key")
                }
            }

            if let elevenStatusMessage {
                Text(elevenStatusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(elevenStatusColor)
                    .transition(.opacity)
            }

            Link(destination: Self.elevenLabsKeysURL) {
                HStack(spacing: 4) {
                    Text("Get an API key")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private var elevenStatusColor: Color {
        switch elevenStatusKind {
        case .neutral: return .secondary
        case .success: return .green
        case .failure: return .orange
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Privacy")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Cloud models upload your audio to the provider. Local models keep audio on this Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch statusKind {
        case .neutral: return .secondary
        case .success: return .green
        case .failure: return .orange
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
