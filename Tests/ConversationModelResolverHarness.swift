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
private typealias Resolution = ConversationModelResolver.Resolution

private func local(_ id: String, languages: Int) -> Candidate {
    Candidate(id: id, provider: nil, backendModelId: id, isRealtime: false, languageCount: languages)
}

private func cloud(_ id: String, _ provider: String, backend: String, realtime: Bool, languages: Int = 99) -> Candidate {
    Candidate(id: id, provider: provider, backendModelId: backend, isRealtime: realtime, languageCount: languages)
}

/// Mirrors the shape and order of `ModelCatalog.all`: the ids, providers,
/// backend models and language counts that decide the resolution.
private let parakeet = local("parakeet-tdt-v3", languages: 25)
private let whisperTurbo = local("whisper-large-v3-turbo", languages: 99)
private let whisperLarge = local("whisper-large-v3", languages: 99)
private let whisperSmall = local("whisper-small", languages: 99)
private let scribeRealtime = cloud("elevenlabs-scribe-v2-realtime", "elevenLabs", backend: "scribe_v2_realtime", realtime: true, languages: 90)
private let liveTranscribe = cloud("openai-gpt-live-transcribe", "openAI", backend: "gpt-live-transcribe", realtime: true)
private let realtimeWhisper = cloud("openai-gpt-realtime-whisper", "openAI", backend: "gpt-realtime-whisper", realtime: true)
private let fourORealtime = cloud("openai-gpt-4o-transcribe-realtime", "openAI", backend: "gpt-4o-transcribe", realtime: true)
private let gptTranscribe = cloud("openai-gpt-transcribe", "openAI", backend: "gpt-transcribe", realtime: false)
private let fourO = cloud("openai-gpt-4o-transcribe", "openAI", backend: "gpt-4o-transcribe", realtime: false)
private let diarize = cloud("openai-gpt-4o-transcribe-diarize", "openAI", backend: "gpt-4o-transcribe-diarize", realtime: false)
private let whisper1 = cloud("openai-whisper-1", "openAI", backend: "whisper-1", realtime: false)

private let catalog = [
    parakeet, whisperTurbo, whisperLarge, whisperSmall, scribeRealtime, liveTranscribe, realtimeWhisper, fourORealtime,
    gptTranscribe, fourO, diarize, whisper1,
]
private let preferred = ["openAI": "openai-gpt-transcribe"]
private let openAIModels: Set<String> = [gptTranscribe.id, fourO.id, diarize.id, whisper1.id]

private func resolve(
    _ model: Candidate,
    catalog: [Candidate] = catalog,
    preferred: [String: String] = preferred,
    ready: Set<String>
) -> Resolution {
    ConversationModelResolver.resolve(
        model,
        catalog: catalog,
        preferredBatchModelIDs: preferred,
        isReady: { ready.contains($0) },
        defaultLocalModelID: parakeet.id
    )
}

@main
struct ConversationModelResolverHarness {
    static func main() throws {
        try batchModelsPassThrough()
        try realtimeWithBatchTwinUsesTwin()
        try realtimeWithoutTwinUsesProvidersPreferredModel()
        try otherProvidersKeyComesBeforeLocal()
        try installedBroadLocalModelBeatsParakeet()
        try installedParakeetWhenNoBroaderLocalModel()
        try defaultNeedsDownloadWhenNothingIsReady()
        try twinUnavailableFallsToPreferred()
        try preferredMustBeABatchModelInTheCatalog()
        try languageCountsParseTheCatalogField()
        print("Conversation model resolver harness passed")
    }

    private static func batchModelsPassThrough() throws {
        for model in [parakeet, whisperTurbo, gptTranscribe, fourO, diarize, whisper1] {
            try expect(resolve(model, ready: []).id == model.id,
                       "\(model.id) isn't realtime, so conversations use it as chosen, key or not")
        }
        try expect(resolve(whisperTurbo, ready: []).needsDownload, "a chosen local model that isn't installed says so")
        try expect(!resolve(gptTranscribe, ready: []).needsDownload, "a cloud model never needs a download")
    }

    private static func realtimeWithBatchTwinUsesTwin() throws {
        try expect(resolve(fourORealtime, ready: openAIModels) == Resolution(id: fourO.id, needsDownload: false),
                   "GPT-4o Transcribe Realtime maps to the batch model it streams")
    }

    private static func realtimeWithoutTwinUsesProvidersPreferredModel() throws {
        try expect(resolve(liveTranscribe, ready: openAIModels).id == gptTranscribe.id,
                   "GPT Live Transcribe has no batch twin: OpenAI's preferred batch model")
        try expect(resolve(realtimeWhisper, ready: openAIModels).id == gptTranscribe.id,
                   "GPT Realtime Whisper has no batch twin: OpenAI's preferred batch model")
    }

    private static func otherProvidersKeyComesBeforeLocal() throws {
        try expect(resolve(scribeRealtime, ready: openAIModels.union([parakeet.id])).id == gptTranscribe.id,
                   "ElevenLabs has no batch model; with an OpenAI key set, OpenAI's preferred batch model")
    }

    private static func installedBroadLocalModelBeatsParakeet() throws {
        let picked = resolve(scribeRealtime, ready: [parakeet.id, whisperSmall.id, whisperLarge.id])
        try expect(picked == Resolution(id: whisperLarge.id, needsDownload: false),
                   "no cloud key: an installed Whisper (catalog order) over Parakeet for a 90-language live model: \(picked)")
        try expect(resolve(liveTranscribe, ready: [whisperTurbo.id, parakeet.id]).id == whisperTurbo.id,
                   "no OpenAI key: the installed 99-language Whisper")
    }

    private static func installedParakeetWhenNoBroaderLocalModel() throws {
        try expect(resolve(scribeRealtime, ready: [parakeet.id]) == Resolution(id: parakeet.id, needsDownload: false),
                   "only Parakeet installed: Parakeet, no download")
    }

    private static func defaultNeedsDownloadWhenNothingIsReady() throws {
        try expect(resolve(scribeRealtime, ready: []) == Resolution(id: parakeet.id, needsDownload: true),
                   "nothing usable: the default local model, flagged as a download")
        try expect(resolve(fourORealtime, ready: []) == Resolution(id: parakeet.id, needsDownload: true),
                   "no OpenAI key and nothing installed: the default, flagged as a download")
    }

    private static func twinUnavailableFallsToPreferred() throws {
        try expect(resolve(fourORealtime, ready: [gptTranscribe.id]).id == gptTranscribe.id,
                   "an unavailable twin falls through to the preferred batch model")
    }

    private static func preferredMustBeABatchModelInTheCatalog() throws {
        try expect(resolve(liveTranscribe, preferred: ["openAI": "openai-gpt-9-transcribe"], ready: openAIModels).id == gptTranscribe.id,
                   "a preferred id missing from the catalog falls to the provider's first ready batch model")
        try expect(resolve(liveTranscribe, preferred: ["openAI": realtimeWhisper.id], ready: openAIModels.union([realtimeWhisper.id])).id
                   == gptTranscribe.id,
                   "a preferred id that is itself realtime is never used")
        try expect(resolve(liveTranscribe, preferred: [:], ready: [parakeet.id]).id == parakeet.id,
                   "no key and no preferred model: installed local")
    }

    private static func languageCountsParseTheCatalogField() throws {
        typealias R = ConversationModelResolver
        try expect(R.languageCount(from: "99") == 99, "bare count")
        try expect(R.languageCount(from: "99+") == 99 && R.languageCount(from: "90+") == 90, "plus suffix")
        try expect(R.languageCount(from: "25 European languages") == 25, "count with words")
        try expect(R.languageCount(from: "many") == 0, "no number")
    }
}
