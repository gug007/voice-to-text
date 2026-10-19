import Foundation

/// A service that transcribes on its own servers, billed to the user's own
/// API key. Its own file, Foundation-only and `nonisolated`, so the pure
/// types that reason about a provider's account — `CloudCreditStatus` — can
/// be compiled by a harness without the model catalog.
nonisolated enum CloudProvider: String, Sendable, Hashable, CaseIterable {
    case openAI
    case elevenLabs
    case groq

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .elevenLabs: return "ElevenLabs"
        case .groq: return "Groq"
        }
    }

    /// "an OpenAI API key", "a Groq API key" — for the sentences that say a
    /// model needs one. The article follows how the name is said, which no
    /// rule on its spelling gets right ("an ElevenLabs").
    var apiKeyPhrase: String {
        switch self {
        case .openAI, .elevenLabs: return "an \(displayName) API key"
        case .groq: return "a \(displayName) API key"
        }
    }

    /// Posted by the provider's key store whenever its API key is set,
    /// cleared, or turns up late from the Keychain. The key stores take
    /// their `didChangeNotification` from here, so whatever reacts to a key
    /// change — readiness, an out-of-credit flag — can observe it without
    /// depending on the stores themselves.
    var keyDidChangeNotification: Notification.Name {
        switch self {
        case .openAI: return Notification.Name("OpenAIAPIKeyStore.didChange")
        case .elevenLabs: return Notification.Name("ElevenLabsAPIKeyStore.didChange")
        case .groq: return Notification.Name("GroqAPIKeyStore.didChange")
        }
    }
}
