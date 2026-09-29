import Foundation

struct ConversationModelResolverHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw ConversationModelResolverHarnessFailure(description: message)
    }
}

private typealias Candidate = ConversationModelResolver.Candidate

private func local(_ id: String) -> Candidate {
    Candidate(id: id, provider: nil, backendModelId: id, isRealtime: false)
}

private func cloud(_ id: String, _ provider: String, backend: String, realtime: Bool) -> Candidate {
    Candidate(id: id, provider: provider, backendModelId: backend, isRealtime: realtime)
}

/// Mirrors the shape of `ModelCatalog.all`: the ids, providers and backend
/// models that decide the resolution.
private let parakeet = local("parakeet-tdt-v3")
private let whisperTurbo = local("whisper-large-v3-turbo")
private let scribeRealtime = cloud("elevenlabs-scribe-v2-realtime", "elevenLabs", backend: "scribe_v2_realtime", realtime: true)
private let liveTranscribe = cloud("openai-gpt-live-transcribe", "openAI", backend: "gpt-live-transcribe", realtime: true)
private let realtimeWhisper = cloud("openai-gpt-realtime-whisper", "openAI", backend: "gpt-realtime-whisper", realtime: true)
private let fourORealtime = cloud("openai-gpt-4o-transcribe-realtime", "openAI", backend: "gpt-4o-transcribe", realtime: true)
private let gptTranscribe = cloud("openai-gpt-transcribe", "openAI", backend: "gpt-transcribe", realtime: false)
private let fourO = cloud("openai-gpt-4o-transcribe", "openAI", backend: "gpt-4o-transcribe", realtime: false)
private let diarize = cloud("openai-gpt-4o-transcribe-diarize", "openAI", backend: "gpt-4o-transcribe-diarize", realtime: false)
private let whisper1 = cloud("openai-whisper-1", "openAI", backend: "whisper-1", realtime: false)

private let catalog = [
    parakeet, whisperTurbo, scribeRealtime, liveTranscribe, realtimeWhisper, fourORealtime,
    gptTranscribe, fourO, diarize, whisper1,
]
private let preferred = ["openAI": "openai-gpt-transcribe"]

private func resolve(
    _ model: Candidate,
    catalog: [Candidate] = catalog,
    preferred: [String: String] = preferred,
    available: Set<String>? = nil
) -> String {
    ConversationModelResolver.resolve(
        model,
        catalog: catalog,
        preferredBatchModelIDs: preferred,
        isAvailable: { id in available?.contains(id) ?? true },
        defaultLocalModelID: parakeet.id
    )
}

@main
struct ConversationModelResolverHarness {
    static func main() throws {
        try batchModelsPassThrough()
        try realtimeWithBatchTwinUsesTwin()
        try realtimeWithoutTwinUsesProvidersPreferredModel()
        try elevenLabsFallsBackToDefaultLocal()
        try unavailableProviderFallsBackToDefaultLocal()
        try twinUnavailableFallsToPreferred()
        try preferredMustBeABatchModelInTheCatalog()
        print("Conversation model resolver harness passed")
    }

    private static func batchModelsPassThrough() throws {
        for model in [parakeet, whisperTurbo, gptTranscribe, fourO, diarize, whisper1] {
            try expect(resolve(model, available: []) == model.id,
                       "\(model.id) isn't realtime, so conversations use it as chosen, key or not")
        }
    }

    private static func realtimeWithBatchTwinUsesTwin() throws {
        try expect(resolve(fourORealtime) == fourO.id,
                   "GPT-4o Transcribe Realtime maps to the batch model it streams")
    }

    private static func realtimeWithoutTwinUsesProvidersPreferredModel() throws {
        try expect(resolve(liveTranscribe) == gptTranscribe.id,
                   "GPT Live Transcribe has no batch twin: OpenAI's preferred batch model")
        try expect(resolve(realtimeWhisper) == gptTranscribe.id,
                   "GPT Realtime Whisper has no batch twin: OpenAI's preferred batch model")
    }

    private static func elevenLabsFallsBackToDefaultLocal() throws {
        try expect(resolve(scribeRealtime) == parakeet.id,
                   "ElevenLabs has no batch model in the catalog: the default local model")
    }

    private static func unavailableProviderFallsBackToDefaultLocal() throws {
        try expect(resolve(fourORealtime, available: []) == parakeet.id,
                   "no OpenAI key: neither the twin nor the preferred model — the default local model")
        try expect(resolve(liveTranscribe, available: []) == parakeet.id,
                   "no OpenAI key: the default local model")
    }

    private static func twinUnavailableFallsToPreferred() throws {
        try expect(resolve(fourORealtime, available: [gptTranscribe.id]) == gptTranscribe.id,
                   "an unavailable twin falls through to the preferred batch model")
    }

    private static func preferredMustBeABatchModelInTheCatalog() throws {
        try expect(resolve(liveTranscribe, preferred: ["openAI": "openai-gpt-9-transcribe"]) == parakeet.id,
                   "a preferred id missing from the catalog is ignored")
        try expect(resolve(liveTranscribe, preferred: ["openAI": realtimeWhisper.id]) == parakeet.id,
                   "a preferred id that is itself realtime is ignored")
        try expect(resolve(liveTranscribe, preferred: [:]) == parakeet.id,
                   "no preferred model for the provider: the default local model")
    }
}
