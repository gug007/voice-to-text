import SwiftUI

struct CloudPane: View {
    @Bindable private var keyStore = OpenAIAPIKeyStore.shared
    @Bindable private var elevenKeyStore = ElevenLabsAPIKeyStore.shared
    @Bindable private var groqKeyStore = GroqAPIKeyStore.shared
    @Bindable private var credit = CloudCreditStatus.shared
    /// A key just removed, held for its Undo toast and no longer.
    @State private var pendingUndo: PendingUndo?

    /// "8 transcription models" — counted from the catalog so the copy can't
    /// drift from the Models pane.
    private static func models(_ provider: CloudProvider) -> String {
        let count = ModelCatalog.all.filter { $0.backend.cloudProvider == provider }.count
        return count == 1 ? "1 transcription model" : "\(count) transcription models"
    }

    var body: some View {
        PaneScaffold {
            SettingsGroup(
                "Providers",
                footer: "Keys stay on this Mac. Cloud models upload audio; AI actions and summaries send text to OpenAI.",
                dividerInset: CloudProviderRow.textInset
            ) {
                CloudProviderRow(
                    config: .openAI,
                    powers: "\(Self.models(.openAI)) · AI actions and summaries",
                    removalConsequence: "Its transcription models, AI actions and summaries stop working until you add a key again.",
                    hasKey: keyStore.hasKey,
                    keySuffix: keyStore.keySuffix,
                    isOutOfCredit: credit.isOutOfCredit(.openAI),
                    autoFocusesField: true,
                    onRemoved: { pendingUndo = $0 }
                )

                CloudProviderRow(
                    config: .elevenLabs,
                    powers: "\(Self.models(.elevenLabs)) · live streaming",
                    removalConsequence: "Scribe v2 Realtime stops working until you add a key again.",
                    hasKey: elevenKeyStore.hasKey,
                    keySuffix: elevenKeyStore.keySuffix,
                    isOutOfCredit: credit.isOutOfCredit(.elevenLabs),
                    autoFocusesField: false,
                    onRemoved: { pendingUndo = $0 }
                )

                CloudProviderRow(
                    config: .groq,
                    powers: "\(Self.models(.groq)) · fast and low cost",
                    removalConsequence: "Its Whisper models stop working until you add a key again.",
                    hasKey: groqKeyStore.hasKey,
                    keySuffix: groqKeyStore.keySuffix,
                    isOutOfCredit: credit.isOutOfCredit(.groq),
                    autoFocusesField: false,
                    onRemoved: { pendingUndo = $0 }
                )
            }
        }
        .overlay { UndoRemovalBar(pending: $pendingUndo) }
    }
}

// MARK: - Provider tiles

extension CloudProvider {
    /// One neutral tile for every provider, told apart by glyph; colour is
    /// left to status. Shared by Cloud and Actions.
    var tileSymbol: String {
        switch self {
        case .openAI: return "sparkle"
        case .elevenLabs: return "waveform"
        case .groq: return "bolt.fill"
        }
    }

    var tileTint: Color { Palette.inkMuted }
}

// MARK: - Key checks

/// The last Test (or connect) verdict per provider, for this run of the app,
/// tied to the key it checked: a different key hides it.
@Observable
final class CloudKeyChecks {
    static let shared = CloudKeyChecks()

    struct Check {
        let keySuffix: String?
        let date: Date
        let verdict: APIKeyVerification
    }

    private var checks: [CloudProvider: Check] = [:]

    func record(_ verdict: APIKeyVerification, for provider: CloudProvider, keySuffix: String?) {
        checks[provider] = Check(keySuffix: keySuffix, date: .now, verdict: verdict)
    }

    func clear(_ provider: CloudProvider) {
        checks[provider] = nil
    }

    func check(for provider: CloudProvider, keySuffix: String?) -> Check? {
        guard let check = checks[provider], check.keySuffix == keySuffix else { return nil }
        return check
    }
}

// MARK: - Provider row

/// One provider in the Cloud group: tile, name, what the key powers, and its
/// state on the trailing edge. Connected, it adds Test and a ⋯ menu
/// (Replace Key…, Remove Key…, Get an API Key); not connected, or while
/// replacing, the key field opens under it.
private struct CloudProviderRow: View {
    let config: APIKeyProviderConfig
    /// What the key unlocks, in one line.
    let powers: String
    /// The removal confirmation's message.
    let removalConsequence: String
    let hasKey: Bool
    let keySuffix: String?
    let isOutOfCredit: Bool
    let autoFocusesField: Bool
    /// Hands Remove's Undo to the pane, which shows the toast.
    let onRemoved: (PendingUndo) -> Void

    private static let tileSize: CGFloat = 34
    /// Where the title starts: the row padding, the tile and its gap. Hairlines
    /// and the key field line up with it.
    static let textInset = FormMetrics.rowHorizontalPadding + tileSize + Space.s5

    @Bindable private var checks = CloudKeyChecks.shared
    @State private var isReplacing = false
    @State private var isTesting = false
    @State private var isConfirmingRemoval = false
    /// "Key removed." / "Key restored", until the next change.
    @State private var note: String?
    /// Focuses the empty field that a removal leaves, for every provider.
    @State private var justRemoved = false
    @Environment(\.openURL) private var openURL
    @Environment(\.motion) private var motion

    private var provider: CloudProvider { config.provider }
    private var lastCheck: CloudKeyChecks.Check? {
        hasKey ? checks.check(for: provider, keySuffix: keySuffix) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(alignment: .center, spacing: Space.s5) {
                ProviderIconTile(symbol: provider.tileSymbol, tint: provider.tileTint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(config.providerName)
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(powers)
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                status
                // Reserved when hidden, so every status ends at one x.
                manageControls
                    .opacity(hasKey ? 1 : 0)
                    .disabled(!hasKey)
                    .accessibilityHidden(!hasKey)
            }

            if let lastCheck, !isReplacing {
                checkLine(lastCheck)
                    .padding(.leading, Self.tileSize + Space.s5)
                    .transition(.opacity)
            } else if let note {
                Text(note)
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.leading, Self.tileSize + Space.s5)
                    .transition(.opacity)
            }

            if !hasKey || isReplacing {
                APIKeyEntryView(
                    config: config,
                    fieldLabel: hasKey ? "New API key" : "API key",
                    autoFocusesField: isReplacing || autoFocusesField || justRemoved,
                    onVerified: { verdict in
                        checks.record(verdict, for: provider, keySuffix: config.keySuffix())
                    },
                    onCancel: isReplacing ? { isReplacing = false } : nil,
                    onConnected: {
                        isReplacing = false
                        justRemoved = false
                        note = nil
                    }
                )
                .padding(.leading, Self.tileSize + Space.s5)
                .transition(.opacity)
            }
        }
        .settingsRowPadding()
        .animation(motion.layout, value: isReplacing)
        .animation(motion.layout, value: hasKey)
        .confirmationDialog(
            "Remove your \(config.providerName) key?",
            isPresented: $isConfirmingRemoval
        ) {
            Button("Remove Key", role: .destructive) { removeKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalConsequence)
        }
    }

    // MARK: - Status

    /// Trailing state. A provider with no key is only "Not connected" unless
    /// something the user chose runs on it (`ProviderKeyNeed`); then it warns,
    /// and says what. "Out of credit" replaces "Connected" once the provider
    /// has refused a take for an empty balance: the key is fine, the account
    /// behind it isn't.
    @ViewBuilder
    private var status: some View {
        if hasKey {
            // A test verdict stays in its dated line under the row, not here:
            // a key fixed at the provider shouldn't read "Rejected" all day.
            if isOutOfCredit {
                StatusLabel(level: .warning, text: withSuffix(FailureCardCopy.outOfCreditLabel))
            } else {
                StatusLabel(level: .ready, text: withSuffix("Connected"))
            }
        } else if let reason = ProviderKeyNeed.current(for: provider).statusText {
            StatusLabel(level: .warning, text: reason)
        } else {
            HStack(spacing: Space.s2) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Not connected")
                    .typo(.caption)
            }
            .foregroundStyle(Palette.inkMuted)
            .fixedSize()
        }
    }

    private func withSuffix(_ text: String) -> String {
        guard let keySuffix else { return text }
        return "\(text) · …\(keySuffix)"
    }

    /// The last Test result, kept until the key changes.
    private func checkLine(_ check: CloudKeyChecks.Check) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let when = Self.relative(check.date, now: context.date)
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                switch check.verdict {
                case .ok:
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.signalReady)
                    Text("Works · tested \(when)")
                case .rejected:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.signalWarn)
                    Text("\(config.providerName) rejected this key · tested \(when). Use Replace Key… in the ⋯ menu.")
                case .failed(let detail):
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(Palette.inkMuted)
                    Text("Couldn't verify · \(detail) · \(when)")
                }
            }
            .font(Typo.caption)
            .foregroundStyle(Palette.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    private static func relative(_ date: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    // MARK: - Connected controls

    private var manageControls: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await testStoredKey() }
            } label: {
                if isTesting {
                    HStack(spacing: Space.s3) {
                        ProgressView().controlSize(.mini)
                        Text("Testing…")
                    }
                } else {
                    Text("Test")
                }
            }
            .buttonTier(.secondary)
            .disabled(isTesting || isReplacing)
            .help("Check that \(config.providerName) accepts the saved key")

            IconMenu(label: "Replace or remove the \(config.providerName) key") {
                Button("Replace Key…") {
                    note = nil
                    isReplacing = true
                }
                Button("Remove Key…", role: .destructive) {
                    isConfirmingRemoval = true
                }
                Divider()
                Button("Get an API Key ↗") { openURL(config.getKeyURL) }
            }
            // No removal while a test or a replacement is in flight.
            .disabled(isTesting || isReplacing)
        }
        .fixedSize()
    }

    // MARK: - Actions

    private func testStoredKey() async {
        guard !isTesting else { return }
        isTesting = true
        defer { isTesting = false }
        let verdict = await config.verifyStored()
        checks.record(verdict, for: provider, keySuffix: keySuffix)
        note = nil
        AccessibilityNotification.Announcement(Self.announcement(for: verdict, provider: config.providerName)).post()
    }

    private static func announcement(for verdict: APIKeyVerification, provider: String) -> String {
        switch verdict {
        case .ok: return "\(provider) key works."
        case .rejected: return "\(provider) rejected this key."
        case .failed(let detail): return "Couldn't verify the \(provider) key: \(detail)"
        }
    }

    private func removeKey() {
        let removedKey = config.readKey()
        let outOfCreditSince = CloudCreditStatus.shared.flaggedSince(provider)
        config.clear()
        checks.clear(provider)
        isReplacing = false
        justRemoved = true
        note = "Key removed."
        guard let removedKey else { return }
        let config = config
        let noteBinding = $note
        onRemoved(PendingUndo(title: "\(config.providerName) key removed") {
            // A key pasted since is the one the user wants now.
            guard !config.hasKey() else { return }
            config.save(removedKey)
            // Saving reads as a new key, which clears an out-of-credit flag;
            // this is the same key, so the flag it had comes back with it.
            if let outOfCreditSince {
                CloudCreditStatus.shared.noteFailure(.quotaExhausted, provider: config.provider, at: outOfCreditSince)
            }
            noteBinding.wrappedValue = Self.restoredMessage(suffix: config.keySuffix())
        })
    }

    private static func restoredMessage(suffix: String?) -> String {
        guard let suffix else { return "Key restored." }
        return "Key restored — ending in …\(suffix)"
    }
}
