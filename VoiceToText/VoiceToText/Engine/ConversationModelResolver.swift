import Foundation

/// Picks the model that transcribes a conversation or imported file when the
/// one asked for — in practice "Same as dictation" with a live dictation model
/// — is a realtime engine.
///
/// Realtime engines are built for a microphone stream. Given a finished
/// recording they fall back to feeding it through a one-shot session, which
/// could end at the first commit, so a whole meeting came back clipped under a
/// success banner. Conversations get a batch model instead, picked the same way
/// every time: the same provider's batch twin (same backend model), else that
/// provider's preferred batch model — either only while the provider is usable
/// (its key is set) — else the default local model.
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
    }

    /// - Parameters:
    ///   - preferredBatchModelIDs: per provider, the batch model to use when a
    ///     realtime model has no batch twin.
    ///   - isAvailable: whether a cloud model can run right now (its key is set).
    /// - Returns: the id of the model to transcribe with.
    static func resolve(
        _ requested: Candidate,
        catalog: [Candidate],
        preferredBatchModelIDs: [String: String],
        isAvailable: (String) -> Bool,
        defaultLocalModelID: String
    ) -> String {
        guard requested.isRealtime else { return requested.id }
        if let provider = requested.provider {
            let batch = catalog.filter { $0.provider == provider && !$0.isRealtime }
            if let twin = batch.first(where: { $0.backendModelId == requested.backendModelId }),
               isAvailable(twin.id) {
                return twin.id
            }
            if let preferred = preferredBatchModelIDs[provider],
               batch.contains(where: { $0.id == preferred }),
               isAvailable(preferred) {
                return preferred
            }
        }
        return defaultLocalModelID
    }
}
