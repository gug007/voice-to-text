import SwiftUI

struct CloudPane: View {
    @Bindable private var keyStore = OpenAIAPIKeyStore.shared
    @Bindable private var elevenKeyStore = ElevenLabsAPIKeyStore.shared
    @Bindable private var credit = CloudCreditStatus.shared

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
                subtitle: "GPT Realtime Whisper, GPT-4o Transcribe, Whisper-1 · AI actions, summaries and action items",
                hasKey: keyStore.hasKey,
                keySuffix: keyStore.keySuffix,
                isOutOfCredit: credit.isOutOfCredit(.openAI),
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
                isOutOfCredit: credit.isOutOfCredit(.elevenLabs),
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
        isOutOfCredit: Bool,
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
                        level: hasKey && !isOutOfCredit ? .ready : .warning,
                        text: statusText(hasKey: hasKey, keySuffix: keySuffix, isOutOfCredit: isOutOfCredit)
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

    /// "Out of credit" takes the place of "Connected" once the provider has
    /// refused a take for an empty balance: the key is fine, the account
    /// behind it isn't. It clears on the next request that works or on a new
    /// key pasted below, so this pane is also where it goes away. No billing
    /// link — the provider's own dashboard is the place for that, and its
    /// URL is theirs to move.
    private func statusText(hasKey: Bool, keySuffix: String?, isOutOfCredit: Bool) -> String {
        guard hasKey else { return "Not set" }
        let status = isOutOfCredit ? FailureCardCopy.outOfCreditLabel : "Connected"
        guard let keySuffix else { return status }
        return "\(status) · …\(keySuffix)"
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
