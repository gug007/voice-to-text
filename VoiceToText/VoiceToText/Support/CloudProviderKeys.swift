import Foundation

/// The one place that maps a cloud provider to its key store. Model rows,
/// settings panes and the dictation pre-flight all ask the same question —
/// "does this provider have a key?" — and used to each answer it with their own
/// switch, which is how an OpenAI-only key once made the ElevenLabs row read
/// "Connected".
extension CloudProvider {
    @MainActor
    var hasAPIKey: Bool {
        switch self {
        case .openAI: return OpenAIAPIKeyStore.shared.hasKey
        case .elevenLabs: return ElevenLabsAPIKeyStore.shared.hasKey
        }
    }

    @MainActor
    var apiKeySuffix: String? {
        switch self {
        case .openAI: return OpenAIAPIKeyStore.shared.keySuffix
        case .elevenLabs: return ElevenLabsAPIKeyStore.shared.keySuffix
        }
    }
}
