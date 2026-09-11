import SwiftUI

struct CloudPane: View {
    @Bindable private var keyStore = OpenAIAPIKeyStore.shared
    @Bindable private var elevenKeyStore = ElevenLabsAPIKeyStore.shared

    /// The two provider tints, as light/dark pairs — raw `.blue` / `.purple`
    /// are not tokens and read differently in each appearance.
    private static let openAITint = Palette.accent
    private static let elevenLabsTint = Palette.dynamic(
        "providerElevenLabs", light: 0x5856D6, dark: 0x7D7AFF
    )

    var body: some View {
        PaneScaffold {
            PaneHeader(
                title: "Cloud",
                subtitle: "Connect to online transcription. Your key stays on this Mac."
            )

            providerSection(
                config: .openAI,
                symbol: "cloud.fill",
                tint: Self.openAITint,
                title: "OpenAI",
                subtitle: "GPT Realtime Whisper, GPT-4o Transcribe, Whisper-1",
                hasKey: keyStore.hasKey,
                keySuffix: keyStore.keySuffix,
                autoFocusesField: true
            )

            providerSection(
                config: .elevenLabs,
                symbol: "waveform",
                tint: Self.elevenLabsTint,
                title: "ElevenLabs",
                subtitle: "Scribe v2 Realtime — live streaming transcription",
                hasKey: elevenKeyStore.hasKey,
                keySuffix: elevenKeyStore.keySuffix,
                autoFocusesField: false
            )

            privacyFooter
        }
    }

    // MARK: - Provider section

    /// Header row plus the shared paste-to-connect field. The two providers
    /// differ only in the tile, the copy and which store they read.
    private func providerSection(
        config: APIKeyProviderConfig,
        symbol: String,
        tint: Color,
        title: String,
        subtitle: String,
        hasKey: Bool,
        keySuffix: String?,
        autoFocusesField: Bool
    ) -> some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s6) {
                HStack(alignment: .center, spacing: Space.s5) {
                    ProviderIconTile(symbol: symbol, tint: tint)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(title)
                            .typo(.title)
                            .foregroundStyle(Palette.ink)
                        Text(subtitle)
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Spacer(minLength: Space.s5)
                    StatusLabel(
                        level: hasKey ? .ready : .warning,
                        text: statusText(hasKey: hasKey, keySuffix: keySuffix)
                    )
                }

                APIKeyEntryView(
                    config: config,
                    showsManagementControls: true,
                    autoFocusesField: autoFocusesField
                )
            }
        }
    }

    private func statusText(hasKey: Bool, keySuffix: String?) -> String {
        guard hasKey else { return "Not set" }
        guard let keySuffix else { return "Connected" }
        return "Connected · …\(keySuffix)"
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
}
