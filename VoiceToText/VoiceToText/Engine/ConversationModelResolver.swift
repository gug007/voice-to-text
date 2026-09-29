import Foundation

/// Picks the model that transcribes a conversation or imported file when the
/// one asked for — in practice "Same as dictation" with a live dictation model
/// — is a realtime engine.
///
/// Realtime engines are built for a microphone stream. Given a finished
/// recording they fall back to feeding it through a one-shot session, which
/// could end at the first commit, so a whole meeting came back clipped under a
/// success banner. Conversations get a batch model instead, picked the same way
/// every time, in this order:
///
/// 1. the same provider's batch twin (same backend model), else that
///    provider's preferred batch model — while its key is set;
/// 2. another provider's batch model whose key is set, so audio the user
///    already sends to the cloud doesn't land on a local model that covers
///    fewer languages;
/// 3. a local model already on this Mac, preferring one that covers as many
///    languages as the live model did (a Whisper model over Parakeet);
/// 4. the default local model, even though that means a download first.
///
/// Foundation-only and fed plain values, so the harness can pin every branch
/// without the catalog or the registry.
nonisolated enum ConversationModelResolver {
    struct Candidate: Equatable, Sendable {
        let id: String
        /// The cloud provider's identifier; nil for a local model.
        let provider: String?
        let backendModelId: String
        let isRealtime: Bool
        /// How many languages the catalog says the model covers.
        let languageCount: Int
    }

    struct Resolution: Equatable, Sendable {
        let id: String
        /// A local model not on this Mac yet: transcribing starts a download.
        let needsDownload: Bool
    }

    /// - Parameters:
    ///   - preferredBatchModelIDs: per provider, the batch model to use when a
    ///     realtime model has no batch twin.
    ///   - isReady: a cloud model's key is set, or a local model is installed.
    static func resolve(
        _ requested: Candidate,
        catalog: [Candidate],
        preferredBatchModelIDs: [String: String],
        isReady: (String) -> Bool,
        defaultLocalModelID: String
    ) -> Resolution {
        guard requested.isRealtime else {
            return Resolution(id: requested.id, needsDownload: requested.provider == nil && !isReady(requested.id))
        }
        let batch = catalog.filter { !$0.isRealtime }

        if let provider = requested.provider,
           let id = cloudChoice(provider: provider, twinOf: requested, batch: batch, preferred: preferredBatchModelIDs, isReady: isReady) {
            return Resolution(id: id, needsDownload: false)
        }

        var otherProviders: [String] = []
        for candidate in batch {
            guard let provider = candidate.provider, provider != requested.provider,
                  !otherProviders.contains(provider) else { continue }
            otherProviders.append(provider)
        }
        for provider in otherProviders {
            if let id = cloudChoice(provider: provider, twinOf: nil, batch: batch, preferred: preferredBatchModelIDs, isReady: isReady) {
                return Resolution(id: id, needsDownload: false)
            }
        }

        let installedLocal = batch.filter { $0.provider == nil && isReady($0.id) }
        if let broad = installedLocal.first(where: { $0.languageCount >= requested.languageCount }) ?? installedLocal.first {
            return Resolution(id: broad.id, needsDownload: false)
        }

        return Resolution(id: defaultLocalModelID, needsDownload: !isReady(defaultLocalModelID))
    }

    /// The catalog's language field as a count: "99", "90+", "25 European
    /// languages" → 99, 90, 25. Anything without a leading number is 0.
    static func languageCount(from languages: String) -> Int {
        Int(languages.prefix(while: \.isNumber)) ?? 0
    }

    /// A provider's twin of `twinOf`, else its preferred batch model, else its
    /// first ready batch model in catalog order.
    private static func cloudChoice(
        provider: String,
        twinOf requested: Candidate?,
        batch: [Candidate],
        preferred: [String: String],
        isReady: (String) -> Bool
    ) -> String? {
        let own = batch.filter { $0.provider == provider }
        if let requested,
           let twin = own.first(where: { $0.backendModelId == requested.backendModelId }),
           isReady(twin.id) {
            return twin.id
        }
        if let preferredID = preferred[provider],
           own.contains(where: { $0.id == preferredID }),
           isReady(preferredID) {
            return preferredID
        }
        return own.first(where: { isReady($0.id) })?.id
    }
}
