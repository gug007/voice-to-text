#if DEBUG
import Foundation

/// Debug builds only: makes the cloud engines refuse every take as an
/// account with no credit would, without sending any audio — so the
/// out-of-credit card, History row and Settings states can be walked live
/// without draining a real balance. Turn it on with
/// `defaults write <bundle id> debug.simulateCloudQuota -bool YES`.
///
/// The whole type, and every call to it, sits behind `#if DEBUG`: a Release
/// build has nothing here to switch on.
nonisolated enum CloudQuotaSimulation {
    static let defaultsKey = "debug.simulateCloudQuota"

    /// Throws `provider`'s empty-balance refusal when the simulation is on.
    /// Call where the engine would first reach the provider, after its API
    /// key check — the refusal a real request gets needs a key too.
    static func throwIfEnabled(for provider: CloudProvider) throws {
        guard UserDefaults.standard.bool(forKey: defaultsKey) else { return }
        switch provider {
        case .openAI:
            // OpenAI's own words for an empty balance, on its own status and code.
            throw CloudTranscriptionError(
                cause: .http(status: 429, retryAfter: nil, apiCode: "insufficient_quota"),
                reason: "OpenAI: You exceeded your current quota, please check your plan and billing details."
            )
        case .elevenLabs:
            // What the ElevenLabs engine throws for its `quota_exceeded` event.
            throw RealtimeFinishPolicy.failureError(
                provider: provider.displayName,
                .refused(
                    .quotaExceeded,
                    "This request exceeds your quota. You have 0 credits remaining, while 25 credits are required for this request."
                ),
                transport: nil
            )
        }
    }
}
#endif
