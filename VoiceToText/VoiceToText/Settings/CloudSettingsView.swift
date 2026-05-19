import SwiftUI

struct CloudPane: View {
    @Bindable private var keyStore = OpenAIAPIKeyStore.shared
    @State private var draftKey: String = ""
    @State private var statusMessage: String?
    @State private var statusKind: StatusKind = .neutral
    @State private var isTesting: Bool = false

    private enum StatusKind { case neutral, success, failure }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(
                    title: "Cloud",
                    subtitle: "API keys for cloud transcription providers. Keys are stored in your macOS Keychain."
                )

                openAICard

                privacyCard
            }
            .padding(32)
        }
        .onAppear {
            draftKey = ""
            statusMessage = nil
            statusKind = .neutral
        }
    }

    @ViewBuilder
    private var openAICard: some View {
        RowCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OpenAI API key")
                            .font(.system(size: 14, weight: .medium))
                        Text("Used for Whisper-1, GPT-4o Transcribe, and GPT-4o Mini Transcribe.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    keyStateBadge
                }

                SecureField("sk-…", text: $draftKey, prompt: Text(keyStore.hasKey ? "Replace existing key" : "Paste your OpenAI API key"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .disableAutocorrection(true)
                    .onSubmit { save() }

                HStack(spacing: 10) {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Test Connection") { Task { await testConnection() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!keyStore.hasKey || isTesting)

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    if keyStore.hasKey {
                        Button(role: .destructive) {
                            keyStore.clearKey()
                            draftKey = ""
                            setStatus("API key removed.", kind: .neutral)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)
                }

                Link("Get an API key from platform.openai.com →",
                     destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.system(size: 11))
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var privacyCard: some View {
        RowCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Privacy")
                    .font(.system(size: 13, weight: .medium))
                Text("When a cloud model is active, your recorded audio is uploaded to that provider for transcription. Local models (Parakeet, Whisper-large) keep audio on your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var keyStateBadge: some View {
        if keyStore.hasKey {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11))
                Text("Configured")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Not set")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
        }
    }

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
        do {
            try keyStore.setKey(trimmed)
            draftKey = ""
            setStatus("API key saved to Keychain.", kind: .success)
        } catch {
            setStatus("Could not save key: \(error.localizedDescription)", kind: .failure)
        }
    }

    private func testConnection() async {
        guard let apiKey = OpenAIAPIKey.read() else {
            setStatus("No API key configured.", kind: .failure)
            return
        }
        isTesting = true
        defer { isTesting = false }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                setStatus("Test failed: invalid response.", kind: .failure)
                return
            }
            switch http.statusCode {
            case 200..<300:
                setStatus("Connection OK — key accepted.", kind: .success)
            case 401:
                setStatus("HTTP 401 — key was rejected by OpenAI.", kind: .failure)
            default:
                setStatus("Test failed: HTTP \(http.statusCode).", kind: .failure)
            }
        } catch {
            setStatus("Test failed: \(error.localizedDescription)", kind: .failure)
        }
    }
}
