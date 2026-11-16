import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey = ""
    @State private var keyError: String?
    @State private var confirmDeleteModel = false

    var body: some View {
        let transcriber = Transcriber.shared
        let keys = OpenAIKeyStore.shared
        let library = Library.shared

        NavigationStack {
            Form {
                Section {
                    LabeledContent("Parakeet TDT v3", value: modelStatus(transcriber.modelState))
                    switch transcriber.modelState {
                    case .preparing(let fraction, let message):
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: min(max(fraction, 0), 1))
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                    case .failed(let message):
                        Text(message).font(.footnote).foregroundStyle(Palette.live)
                        Button("Try again") { transcriber.prepareModel() }
                    case .missing where !Transcriber.isModelDownloaded:
                        Button("Download (about \(Transcriber.approxDownloadMB) MB)") { transcriber.prepareModel() }
                    default:
                        Button("Delete model", role: .destructive) { confirmDeleteModel = true }
                            .disabled(transcriber.activeID != nil)
                    }
                } header: {
                    Text("Speech model")
                } footer: {
                    Text("Transcribes on this iPhone in 25 European languages. Your audio never leaves the device.")
                }

                Section {
                    if let suffix = keys.suffix {
                        LabeledContent("API key", value: "•••• \(suffix)")
                        Button("Remove key", role: .destructive) { keys.clear() }
                    } else {
                        SecureField("sk-…", text: $draftKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save key") {
                            if keys.set(draftKey) {
                                draftKey = ""
                                keyError = nil
                            } else {
                                keyError = "The key couldn't be saved."
                            }
                        }
                        .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let keyError {
                            Text(keyError).font(.footnote).foregroundStyle(Palette.live)
                        }
                    }
                } header: {
                    Text("OpenAI")
                } footer: {
                    Text("Only Summary and Action Items use this key. They send the transcript text to OpenAI and are billed to your account. The key is kept in this iPhone's Keychain.")
                }

                MacSettingsSection()

                Section("Storage") {
                    LabeledContent("Recordings", value: "\(library.entries.count)")
                    LabeledContent(
                        "Space used",
                        value: ByteCountFormatter.string(fromByteCount: library.diskUsageBytes, countStyle: .file)
                    )
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: loginPage) { page in
                SafariView(url: page.url) { MacRemote.shared.cancelSignIn() }
                    .ignoresSafeArea()
            }
            .confirmationDialog("Delete the speech model?", isPresented: $confirmDeleteModel, titleVisibility: .visible) {
                Button("Delete model", role: .destructive) { transcriber.deleteModel() }
            } message: {
                Text("Recordings are kept. Transcribing again needs a new download.")
            }
        }
    }

    private var loginPage: Binding<LoginPage?> {
        Binding(
            get: {
                if case .needsLogin(let url) = MacRemote.shared.tailnet.state { return LoginPage(url: url) }
                return nil
            },
            set: { page in
                if page == nil, case .needsLogin = MacRemote.shared.tailnet.state { MacRemote.shared.cancelSignIn() }
            }
        )
    }

    private func modelStatus(_ state: Transcriber.ModelState) -> String {
        switch state {
        case .ready: return "Ready"
        case .preparing: return "Preparing"
        case .failed: return "Failed"
        case .missing: return Transcriber.isModelDownloaded ? "On this iPhone" : "Not downloaded"
        }
    }
}
