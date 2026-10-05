import Foundation
import Observation
import OSLog

struct ModelDescriptor: Identifiable, Hashable, Sendable {
    enum Backend: String, Sendable, Hashable {
        case whisperKit
        case fluidAudio
        case openAI
        case openAIRealtime
        case elevenLabs

        var cloudProvider: CloudProvider? {
            switch self {
            case .whisperKit, .fluidAudio: return nil
            case .openAI, .openAIRealtime: return .openAI
            case .elevenLabs: return .elevenLabs
            }
        }

        var isCloud: Bool { cloudProvider != nil }

        /// True for engines that transcribe a live audio stream — partials
        /// appear as the user speaks — rather than a buffered recording.
        var isStreaming: Bool {
            switch self {
            case .elevenLabs, .openAIRealtime: return true
            case .whisperKit, .fluidAudio, .openAI: return false
            }
        }
    }

    let id: String
    let displayName: String
    let backend: Backend
    let backendModelId: String
    let approxSizeMB: Int
    let languages: String
    /// The languages this model transcribes, as lowercase ISO 639-1 codes —
    /// what `DictationTakePolicy.localFallback` checks the languages the user
    /// speaks against before offering it in place of a cloud model. `nil`
    /// means broadly multilingual (Whisper's 99): no list worth checking.
    /// `languages` is the same fact worded for the Models pane.
    var languageCodes: Set<String>? = nil
    /// Whether the app may choose this local model on the user's behalf — as
    /// the model a failure card offers when the cloud one can't run. False
    /// for the models whose own notes warn off real use (Whisper Base and
    /// Tiny): offering one of those as the way out would trade a refused
    /// request for a transcript full of mistakes. The user can still pick
    /// them anywhere. Only read for local models; cloud ones are never
    /// fallback candidates.
    var autoPickable: Bool = true
    let notes: String
    let speed: Int
    /// Provider list price in USD per hour of audio, as published on the
    /// provider's pricing page in September 2026. `0` for local models (they cost
    /// nothing to run); `nil` when a price is not known, in which case the Models
    /// row omits the segment rather than guessing. Cloud usage is billed by the
    /// provider to the user's own API key, never by this app, so this is a
    /// courtesy estimate — per-minute list prices multiplied by 60.
    let pricePerHourUSD: Double?
    /// Published word error rates for this model, as of the September 2026
    /// snapshot. Artificial Analysis AA-WER is the primary source — it is the
    /// one benchmark that measures local models and cloud APIs on the same
    /// audio, and its streaming board is the only one that covers the live APIs
    /// at all. The Hugging Face Open ASR Leaderboard (English average) is the
    /// fallback for open-weights models AA has not run, and Whisper Large v3
    /// appears on both, which is what lets the two scales meet — see
    /// `ModelQualityScore`. Empty when nothing published covers the model, in
    /// which case it has no quality score rather than a guess.
    let benchmarks: [WERMeasurement]

    var isCloud: Bool { backend.isCloud }
    var isRealtime: Bool { backend.isStreaming }

    var resolverCandidate: ConversationModelResolver.Candidate {
        ConversationModelResolver.Candidate(
            id: id,
            provider: backend.cloudProvider?.rawValue,
            backendModelId: backendModelId,
            isRealtime: isRealtime,
            languageCount: ConversationModelResolver.languageCount(from: languages)
        )
    }

    /// 1...10 accuracy score derived from `benchmarks`; `nil` when unmeasured.
    var quality: Double? { ModelQualityScore.score(for: benchmarks) }

    /// True when `quality` rests on indirect evidence rather than an
    /// Artificial Analysis figure of this model's own, so the Models row
    /// prefixes the score with "≈".
    var isQualityApproximate: Bool { ModelQualityScore.isApproximate(benchmarks) }
}

enum ModelCatalog {
    static let all: [ModelDescriptor] = [
        ModelDescriptor(
            id: "parakeet-tdt-v3",
            displayName: "Parakeet TDT v3",
            backend: .fluidAudio,
            backendModelId: "parakeet-tdt-v3",
            approxSizeMB: 470,
            languages: "25 European languages",
            languageCodes: [
                "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
                "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
            ],
            notes: "Fastest on your Mac. Best for English and major European languages.",
            speed: 10,
            pricePerHourUSD: 0,
            benchmarks: [
                WERMeasurement(
                    benchmark: .artificialAnalysis,
                    percent: 6.4,
                    isEstimate: true,
                    note: "Artificial Analysis has not benchmarked v3; this is its predecessor Parakeet TDT 0.6B v2's figure."
                ),
                WERMeasurement(benchmark: .openASRLeaderboard, percent: 6.32, isEstimate: false, note: nil),
            ]
        ),
        ModelDescriptor(
            id: "whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo",
            backend: .whisperKit,
            backendModelId: "openai_whisper-large-v3-v20240930_turbo",
            approxSizeMB: 632,
            languages: "99",
            notes: "Excellent accuracy in 99 languages. A great all-rounder.",
            speed: 7,
            pricePerHourUSD: 0,
            benchmarks: [
                WERMeasurement(benchmark: .openASRLeaderboard, percent: 7.75, isEstimate: false, note: nil),
                WERMeasurement(
                    benchmark: .artificialAnalysis,
                    percent: 4.6,
                    isEstimate: false,
                    note: "Best-host figure (Groq)."
                ),
            ]
        ),
        ModelDescriptor(
            id: "whisper-large-v3",
            displayName: "Whisper Large v3",
            backend: .whisperKit,
            backendModelId: "openai_whisper-large-v3-v20240930",
            approxSizeMB: 626,
            languages: "99",
            notes: "Extremely accurate offline. Noticeably slower than Turbo.",
            speed: 3,
            pricePerHourUSD: 0,
            benchmarks: [
                WERMeasurement(benchmark: .openASRLeaderboard, percent: 7.44, isEstimate: false, note: nil),
                WERMeasurement(
                    benchmark: .artificialAnalysis,
                    percent: 4.1,
                    isEstimate: false,
                    note: "Best-host figure (fal.ai)."
                ),
            ]
        ),
        ModelDescriptor(
            id: "whisper-small",
            displayName: "Whisper Small",
            backend: .whisperKit,
            backendModelId: "openai_whisper-small",
            approxSizeMB: 244,
            languages: "99",
            notes: "Smaller and faster, but makes more mistakes.",
            speed: 8,
            pricePerHourUSD: 0,
            benchmarks: [
                WERMeasurement(benchmark: .openASRLeaderboard, percent: 8.59, isEstimate: false, note: nil),
            ]
        ),
        ModelDescriptor(
            id: "whisper-base",
            displayName: "Whisper Base",
            backend: .whisperKit,
            backendModelId: "openai_whisper-base",
            approxSizeMB: 77,
            languages: "99",
            autoPickable: false,
            notes: "Very small. Quite a few mistakes — only worth it on slow Macs.",
            speed: 9,
            pricePerHourUSD: 0,
            benchmarks: [
                WERMeasurement(benchmark: .openASRLeaderboard, percent: 10.32, isEstimate: false, note: nil),
            ]
        ),
        ModelDescriptor(
            id: "whisper-tiny",
            displayName: "Whisper Tiny",
            backend: .whisperKit,
            backendModelId: "openai_whisper-tiny",
            approxSizeMB: 39,
            languages: "99",
            autoPickable: false,
            notes: "Smallest. Lots of mistakes — mainly useful for testing.",
            speed: 10,
            pricePerHourUSD: 0,
            benchmarks: [
                WERMeasurement(benchmark: .openASRLeaderboard, percent: 12.81, isEstimate: false, note: nil),
            ]
        ),
        ModelDescriptor(
            id: "elevenlabs-scribe-v2-realtime",
            displayName: "Scribe v2 Realtime (ElevenLabs)",
            backend: .elevenLabs,
            backendModelId: "scribe_v2_realtime",
            approxSizeMB: 0,
            languages: "90+",
            notes: "Live streaming — words appear as you speak. Audio goes to ElevenLabs.",
            speed: 10,
            pricePerHourUSD: 0.39, // $0.39/hr list price
            benchmarks: [
                WERMeasurement(
                    benchmark: .artificialAnalysis,
                    percent: 3.6,
                    isEstimate: false,
                    note: "AA-WER Streaming, final transcript."
                ),
            ]
        ),
        ModelDescriptor(
            id: "openai-gpt-live-transcribe",
            displayName: "GPT Live Transcribe (OpenAI)",
            backend: .openAIRealtime,
            backendModelId: "gpt-live-transcribe",
            approxSizeMB: 0,
            languages: "99+",
            notes: "OpenAI's newest live streaming model — words appear as you speak. Audio goes to OpenAI.",
            speed: 10,
            pricePerHourUSD: 1.02, // $0.017/min
            benchmarks: [
                WERMeasurement(
                    benchmark: .artificialAnalysis,
                    percent: 3.9,
                    isEstimate: false,
                    note: "AA-WER Streaming, final transcript."
                ),
            ]
        ),
        ModelDescriptor(
            id: "openai-gpt-realtime-whisper",
            displayName: "GPT Realtime Whisper (OpenAI)",
            backend: .openAIRealtime,
            backendModelId: "gpt-realtime-whisper",
            approxSizeMB: 0,
            languages: "99+",
            notes: "Live streaming built for the lowest latency. Audio goes to OpenAI.",
            speed: 10,
            pricePerHourUSD: 1.02, // $0.017/min
            benchmarks: [
                WERMeasurement(
                    benchmark: .artificialAnalysis,
                    percent: 4.9,
                    isEstimate: false,
                    note: "AA-WER Streaming, final transcript (7.5% at first partial)."
                ),
            ]
        ),
        ModelDescriptor(
            id: "openai-gpt-4o-transcribe-realtime",
            displayName: "GPT-4o Transcribe Realtime (OpenAI)",
            backend: .openAIRealtime,
            backendModelId: "gpt-4o-transcribe",
            approxSizeMB: 0,
            languages: "99+",
            notes: "Live streaming — words appear as you speak. Audio goes to OpenAI.",
            speed: 9,
            // Realtime sessions bill at the same audio-token rate as the batch
            // gpt-4o-transcribe model.
            pricePerHourUSD: 0.36, // $0.006/min
            benchmarks: [
                WERMeasurement(
                    benchmark: .artificialAnalysis,
                    percent: 4.0,
                    isEstimate: true,
                    note: "Not on the streaming leaderboard; carried over from GPT-4o Transcribe's batch score."
                ),
            ]
        ),
        ModelDescriptor(
            id: "openai-gpt-transcribe",
            displayName: "GPT Transcribe (OpenAI)",
            backend: .openAI,
            backendModelId: "gpt-transcribe",
            approxSizeMB: 0,
            languages: "99+",
            // The highest-scoring cloud model on Artificial Analysis AA-WER
            // (3.3% against GPT-4o Transcribe's 4.0%), so it takes the "Most
            // accurate" chip. That matches OpenAI's own guide: "Start with
            // `gpt-transcribe`. This is the recommended model for transcribing
            // recorded speech in its original language" — GPT-4o Transcribe is
            // now reserved for speaker labels, timestamps, subtitles, or
            // translation. It is also cheaper ($0.0045 vs $0.006/min).
            notes: "OpenAI's recommended transcription model — newer and cheaper than GPT-4o Transcribe. Audio goes to OpenAI.",
            speed: 6,
            pricePerHourUSD: 0.27, // $0.0045/min
            benchmarks: [
                WERMeasurement(benchmark: .artificialAnalysis, percent: 3.3, isEstimate: false, note: nil),
            ]
        ),
        ModelDescriptor(
            id: "openai-gpt-4o-transcribe",
            displayName: "GPT-4o Transcribe (OpenAI)",
            backend: .openAI,
            backendModelId: "gpt-4o-transcribe",
            approxSizeMB: 0,
            languages: "99+",
            // Was "the most accurate option overall" here. Artificial Analysis
            // now measures it at 4.0% AA-WER against gpt-transcribe's 3.3%, so
            // the superlative goes with the chip — it lands a few tenths of a
            // point below, still a strong model, just no longer the one to reach
            // for first. It is also the pricier of the two: $0.006/min against
            // gpt-transcribe's $0.0045.
            notes: "Previous-generation cloud model, still very accurate. Audio goes to OpenAI.",
            speed: 5,
            pricePerHourUSD: 0.36, // $0.006/min
            benchmarks: [
                WERMeasurement(benchmark: .artificialAnalysis, percent: 4.0, isEstimate: false, note: nil),
            ]
        ),
        ModelDescriptor(
            id: "openai-gpt-4o-transcribe-diarize",
            displayName: "GPT-4o Transcribe Diarize (OpenAI)",
            backend: .openAI,
            backendModelId: "gpt-4o-transcribe-diarize",
            approxSizeMB: 0,
            languages: "99+",
            notes: "Labels who said what — best for meetings. Audio goes to OpenAI.",
            speed: 4,
            pricePerHourUSD: 0.36, // $0.006/min, no diarization surcharge
            benchmarks: [
                WERMeasurement(
                    benchmark: .artificialAnalysis,
                    percent: 4.0,
                    isEstimate: true,
                    note: "Not independently benchmarked; OpenAI calls it roughly comparable to GPT-4o Transcribe, whose score this is."
                ),
            ]
        ),
        ModelDescriptor(
            id: "openai-gpt-4o-mini-transcribe",
            displayName: "GPT-4o Mini Transcribe (OpenAI)",
            backend: .openAI,
            backendModelId: "gpt-4o-mini-transcribe",
            approxSizeMB: 0,
            languages: "99+",
            notes: "Nearly as accurate as GPT-4o Transcribe and cheaper to run.",
            speed: 7,
            pricePerHourUSD: 0.18, // $0.003/min
            benchmarks: [
                WERMeasurement(benchmark: .artificialAnalysis, percent: 4.5, isEstimate: false, note: nil),
            ]
        ),
        ModelDescriptor(
            id: "openai-whisper-1",
            displayName: "Whisper-1 (OpenAI)",
            backend: .openAI,
            backendModelId: "whisper-1",
            approxSizeMB: 0,
            languages: "99",
            notes: "OpenAI's older online model. Cheapest, but less accurate than GPT-4o.",
            speed: 6,
            pricePerHourUSD: 0.36, // $0.006/min
            benchmarks: [
                WERMeasurement(
                    benchmark: .artificialAnalysis,
                    percent: 4.1,
                    isEstimate: false,
                    note: "Listed by Artificial Analysis as Whisper Large v2 (OpenAI)."
                ),
            ]
        ),
    ]

    static func model(for id: String) -> ModelDescriptor? {
        all.first { $0.id == id }
    }

    /// The dictation model on a fresh install, and the local model that
    /// conversations fall back to when nothing else fits.
    static let defaultModelID = "parakeet-tdt-v3"

    /// Per provider, the batch model that transcribes conversations in place of
    /// a realtime model with no batch twin (see `ConversationModelResolver`).
    /// OpenAI's own recommendation for recorded speech. ElevenLabs has no batch
    /// model in the catalog, so its live model falls back to the local default.
    static let preferredConversationBatchModelIDs: [CloudProvider: String] = [
        .openAI: "openai-gpt-transcribe",
    ]
}

enum ModelReadiness: Equatable {
    case notInstalled
    case installed(sizeBytes: Int64)
    case preparing(fraction: Double, message: String)
    case failed(String)

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    /// Preparing, in the load/compile tail (CoreML prewarm) rather than
    /// fetching files. The engines report no separate phase for it, only
    /// their progress messages ("Loading model into memory…", "Compiling
    /// AudioEncoder…"), so this reads those. "Downloading 3/12 files"
    /// contains "load" too, so the download phase is ruled out first —
    /// otherwise every download read as unmetered, and the stall watchdog
    /// never evicted one that had stopped.
    var isLoadingOrCompiling: Bool {
        guard case .preparing(_, let message) = self else { return false }
        let lower = message.lowercased()
        if lower.hasPrefix("download") { return false }
        return lower.contains("load") || lower.contains("compil")
    }

    /// Preparing, and not yet past fetching the model's files: the folder on
    /// disk may hold some of them already, but not a model that loads.
    var isDownloading: Bool {
        guard case .preparing = self else { return false }
        return !isLoadingOrCompiling
    }
}

@Observable
@MainActor
final class ModelRegistry {
    private enum Keys {
        static let activeModelId = "activeModelId"
        static let conversationModelId = "conversationModelId"
    }

    static let shared = ModelRegistry()

    private(set) var activeModelId: String

    /// Explicit model for conversations/meetings, independent of dictation.
    /// `nil` means "follow the dictation model" (`activeModel`).
    private(set) var conversationModelId: String?
    private(set) var readiness: [String: ModelReadiness] = [:]

    /// The local models on disk whole — downloaded and loadable offline
    /// (`ModelStorage.isDownloaded`) — as of the last change to what is
    /// installed. `localFallbackCandidates` reads this instead of walking the
    /// model folders and every model's `readiness`, so a History row that
    /// asks for a fallback in its body neither walks the disk on each render
    /// nor re-renders on each download progress tick. Refreshed only where
    /// the answer can change: a preparation that ends (installed, failed or
    /// stalled out), a delete, and `refreshInstalledState`.
    private(set) var downloadedLocalModelIDs: Set<String> = []

    @ObservationIgnored
    private var engines: [String: TranscriptionEngine] = [:]

    /// Ids of the resident **local** engines, least-recently-used first. A local
    /// engine holds its CoreML model in memory for as long as it's referenced,
    /// and nothing but `deleteModel` ever dropped one — so trying a few models
    /// in one session kept every one of them resident until relaunch. Cloud
    /// engines are a URLSession and a few fields, so they stay cached untracked.
    @ObservationIgnored
    private var residentLocalEngines: [String] = []

    /// How many local engines stay warm. Two covers the common case — dictation
    /// and conversations on different models — while switching models releases
    /// the one that fell out instead of stacking it up. An evicted model simply
    /// reloads on its next use; `prepareModel` already handles that path.
    private static let maxResidentLocalEngines = 2

    /// Engines for background batch work (meeting transcription, transcript
    /// regeneration), deliberately never shared with `engines`. An engine runs
    /// one inference at a time, so a meeting chunk-transcribing on dictation's
    /// instance left a short dictation queued behind it for tens of seconds.
    /// One resident is enough: those jobs don't run side by side.
    @ObservationIgnored
    private var backgroundEngines: [String: TranscriptionEngine] = [:]

    @ObservationIgnored
    private var residentBackgroundLocalEngines: [String] = []

    private static let maxResidentBackgroundLocalEngines = 1

    @ObservationIgnored
    private var preparationTasks: [String: Task<TranscriptionEngine?, Never>] = [:]

    @ObservationIgnored
    private var preparationGenerations: [String: UInt64] = [:]

    /// `prepare()` (HuggingFace download, CoreML compile) has no internal
    /// timeout, so a stalled network read parks the caller forever. Treat a
    /// preparation that makes no progress for this long as stuck.
    private static let prepareStallTimeoutMs = 120_000
    /// The same, once files are coming in ("Downloading x/y files").
    /// WhisperKit's Hub downloader reports progress only per 10 MB chunk, and
    /// weighs each file the same whatever its size, so on a slow link a
    /// healthy download can go two minutes without moving. A dead connection
    /// doesn't need this to end it — both libraries' own transport timeouts
    /// (the Hub's 10 s with retries, URLSession's 60 s) get there first — so
    /// this is only the backstop, and a long one costs little.
    private static let downloadStallTimeoutMs = 300_000
    private static let prepareStallPollMs = 1_000

    private init() {
        self.activeModelId = UserDefaults.standard.string(forKey: Keys.activeModelId)
            ?? ModelCatalog.defaultModelID
        self.conversationModelId = UserDefaults.standard.string(forKey: Keys.conversationModelId)
        refreshInstalledState()
        NotificationCenter.default.addObserver(
            forName: OpenAIAPIKeyStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCloudReadiness() }
        }
        NotificationCenter.default.addObserver(
            forName: ElevenLabsAPIKeyStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCloudReadiness() }
        }
    }

    /// Kick off a background download of the active model if it isn't already
    /// installed or being prepared. Safe to call multiple times — no-ops when
    /// the model is already present or a download is in flight.
    func bootstrapActiveModelIfNeeded() {
        let id = activeModelId
        guard let descriptor = ModelCatalog.model(for: id) else { return }
        if descriptor.isCloud { return }
        switch readiness(for: id) {
        case .installed, .preparing:
            return
        case .notInstalled, .failed:
            Task { [weak self] in
                await self?.prepareModel(id: id)
            }
        }
    }

    func refreshInstalledState() {
        for model in ModelCatalog.all {
            updateReadiness(for: model)
        }
        refreshDownloadedLocalModels()
    }

    /// Recomputes `downloadedLocalModelIDs`, assigning only on a change so
    /// its readers aren't invalidated for nothing.
    private func refreshDownloadedLocalModels() {
        let next = Set(ModelCatalog.all.lazy
            .filter { !$0.isCloud && ModelStorage.isDownloaded($0, readiness: self.readiness(for: $0.id)) }
            .map(\.id))
        if next != downloadedLocalModelIDs {
            downloadedLocalModelIDs = next
        }
    }

    /// Cheaper variant used when only API-key-driven readiness can have
    /// changed. Skips disk scans for local models.
    private func refreshCloudReadiness() {
        for model in ModelCatalog.all where model.backend.isCloud {
            updateReadiness(for: model)
        }
    }

    private func updateReadiness(for model: ModelDescriptor) {
        let next: ModelReadiness
        switch model.backend.cloudProvider {
        case .openAI:
            next = OpenAIAPIKey.read() != nil ? .installed(sizeBytes: 0) : .notInstalled
        case .elevenLabs:
            next = ElevenLabsAPIKey.read() != nil ? .installed(sizeBytes: 0) : .notInstalled
        case nil:
            let state = ModelStorage.installedState(model)
            next = state.installed ? .installed(sizeBytes: state.sizeBytes) : .notInstalled
        }
        // Avoid spurious view invalidation: @Observable propagates assignments
        // regardless of equality, so guard with an explicit compare.
        if readiness[model.id] != next {
            readiness[model.id] = next
        }
    }

    var totalDiskUsageBytes: Int64 {
        ModelCatalog.all.reduce(Int64(0)) { total, model in
            if case .installed(let bytes) = readiness[model.id] {
                return total + bytes
            }
            return total
        }
    }

    var activeModel: ModelDescriptor? {
        ModelCatalog.model(for: activeModelId)
    }

    /// Model used to transcribe conversations/meetings: the explicitly chosen
    /// one when set and still present in the catalog (a stale stored id falls
    /// back), otherwise the dictation model — with a live model swapped for a
    /// batch one, since a finished recording is no job for a streaming engine.
    var conversationModel: ModelDescriptor? {
        if let id = conversationModelId, let explicit = ModelCatalog.model(for: id) {
            return conversationTranscription(for: explicit).model
        }
        return dictationModelForConversations?.model
    }

    /// What "Same as dictation" transcribes conversations with right now: the
    /// dictation model, or the batch model standing in for a live one — and
    /// whether that model has to be downloaded first.
    var dictationModelForConversations: (model: ModelDescriptor, needsDownload: Bool)? {
        activeModel.map(conversationTranscription(for:))
    }

    /// `model` itself unless it's realtime; then the batch model that
    /// `ConversationModelResolver` picks. A cloud model counts as ready while
    /// its readiness says the provider's key is set, a local one while it is
    /// installed (or on its way).
    private func conversationTranscription(for model: ModelDescriptor) -> (model: ModelDescriptor, needsDownload: Bool) {
        guard model.isRealtime else { return (model, false) }
        let preferred = Dictionary(uniqueKeysWithValues: ModelCatalog.preferredConversationBatchModelIDs.map {
            ($0.key.rawValue, $0.value)
        })
        let resolution = ConversationModelResolver.resolve(
            model.resolverCandidate,
            catalog: ModelCatalog.all.map(\.resolverCandidate),
            preferredBatchModelIDs: preferred,
            isReady: { [readiness] id in
                switch readiness[id] {
                case .installed, .preparing: return true
                case .notInstalled, .failed, nil: return false
                }
            },
            defaultLocalModelID: ModelCatalog.defaultModelID
        )
        guard let resolved = ModelCatalog.model(for: resolution.id) else { return (model, false) }
        return (resolved, resolution.needsDownload)
    }

    /// The user picked a dictation model. Picking any model — Switch Back
    /// included — ends a switch "Use for Dictation" made, so the Models
    /// pane's "Switched from …" banner goes with it.
    func setActive(_ modelId: String) {
        guard ModelCatalog.model(for: modelId) != nil else { return }
        activeModelId = modelId
        UserDefaults.standard.set(modelId, forKey: Keys.activeModelId)
        CloudCreditStatus.shared.clearSwitchedFrom()
    }

    /// "Use for Dictation" on an out-of-credit failure card: makes the local
    /// `modelId` the dictation model, and remembers `cloudModelId` so the
    /// Models pane can offer to switch back once the balance is topped up.
    /// The one place the rescue changes the dictation model, and only on that
    /// explicit click.
    func useForDictation(_ modelId: String, switchingFrom cloudModelId: String) {
        guard ModelCatalog.model(for: modelId) != nil else { return }
        setActive(modelId)
        CloudCreditStatus.shared.noteSwitchedForDictation(from: cloudModelId)
    }

    /// Sets the conversation model. Pass `nil` to follow the dictation model
    /// (this clears the stored preference).
    func setConversationModel(_ modelId: String?) {
        conversationModelId = modelId
        if let modelId {
            UserDefaults.standard.set(modelId, forKey: Keys.conversationModelId)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.conversationModelId)
        }
    }

    func readiness(for modelId: String) -> ModelReadiness {
        readiness[modelId] ?? .notInstalled
    }

    // MARK: - Local fallback

    /// Every model on this Mac as `DictationTakePolicy.localFallback` weighs
    /// it, in catalog order. Installed means downloaded and loadable offline
    /// (`ModelStorage.isDownloaded`), as History's model menu asks it — read
    /// from `downloadedLocalModelIDs`, so it touches neither the disk nor
    /// `readiness`.
    func localFallbackCandidates() -> [DictationTakePolicy.LocalCandidate] {
        ModelCatalog.all.filter { !$0.isCloud }.map { model in
            DictationTakePolicy.LocalCandidate(
                id: model.id,
                isInstalled: downloadedLocalModelIDs.contains(model.id),
                languageCodes: model.languageCodes,
                sizeMB: model.approxSizeMB,
                autoPickable: model.autoPickable
            )
        }
    }

    /// The model on this Mac to offer in place of `failedModelId`, for the
    /// languages this user dictates in (`SpokenLanguages`, read from their
    /// recent dictations in History). Pass `canDownload: false` offline,
    /// where only a model already here helps. Cheap enough for a view's body:
    /// everything it reads is cached.
    func localFallback(
        replacing failedModelId: String,
        canDownload: Bool
    ) -> DictationTakePolicy.LocalFallback? {
        let spoken = SpokenLanguages.current(recentDictations: Self.recentDictations())
        return DictationTakePolicy.localFallback(
            candidates: localFallbackCandidates(),
            failedModelID: failedModelId,
            spokenLanguages: spoken.languages,
            primaryLanguage: spoken.primary,
            canDownload: canDownload
        )
    }

    /// The newest dictations in History with a real transcript, newest
    /// first — what `SpokenLanguages` reads the user's languages from.
    /// Conversations are left out: half of what they hold is other people.
    private static func recentDictations() -> [SpokenLanguages.Dictation] {
        Array(RecordingHistoryStore.shared.entries.lazy
            .filter { ($0.source ?? .dictation) == .dictation && !$0.transcriptIsPlaceholder }
            .prefix(SpokenLanguages.recentDictationsRead)
            .map { SpokenLanguages.Dictation(id: $0.id, text: $0.transcript) })
    }

    @discardableResult
    func prepareModel(id: String) async -> TranscriptionEngine? {
        guard let descriptor = ModelCatalog.model(for: id) else { return nil }

        if let existing = engines[id], readiness[id]?.isInstalled == true {
            touchResidentEngine(descriptor)
            return existing
        }

        if let existingTask = preparationTasks[id] {
            let generation = preparationGenerations[id] ?? 0
            let engine = await awaitPreparationOrStall(existingTask, id: id)
            if engine == nil { evictStalledPreparation(id: id, generation: generation) }
            return engine
        }

        let generation = nextPreparationGeneration(for: id)
        readiness[id] = .preparing(fraction: 0.0, message: "Starting…")
        let engine = makeEngine(for: descriptor)

        let task = Task<TranscriptionEngine?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            do {
                try await engine.prepare { [weak self] fraction, message in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.isCurrentPreparation(id: id, generation: generation) else { return }
                        self.readiness[id] = .preparing(fraction: fraction, message: message)
                    }
                }
                guard self.isCurrentPreparation(id: id, generation: generation),
                      !Task.isCancelled else { return nil }
                self.engines[id] = engine
                // Touch *before* evicting so the engine we're about to hand back
                // is the newest entry and can never be the one dropped.
                self.touchResidentEngine(descriptor)
                self.readiness[id] = .installed(sizeBytes: ModelStorage.diskUsageBytes(descriptor))
                self.refreshDownloadedLocalModels()
                return engine
            } catch {
                guard self.isCurrentPreparation(id: id, generation: generation),
                      !Task.isCancelled else { return nil }
                self.readiness[id] = .failed(error.localizedDescription)
                self.refreshDownloadedLocalModels()
                return nil
            }
        }
        preparationTasks[id] = task
        let prepared = await awaitPreparationOrStall(task, id: id)
        if isCurrentPreparation(id: id, generation: generation) {
            preparationTasks[id] = nil
        }
        if prepared == nil { evictStalledPreparation(id: id, generation: generation) }
        return prepared
    }

    /// A separate engine instance for background batch transcription. The
    /// download, dedup and stall handling all ride on `prepareModel`; only the
    /// loaded instance differs, so a long meeting can never hold up dictation.
    func prepareBackgroundEngine(id: String) async -> TranscriptionEngine? {
        guard let descriptor = ModelCatalog.model(for: id) else { return nil }

        // A cached cloud engine outlives its API key: handing it back after
        // the key was removed would fail inside the transcription as "Call
        // prepare() first" instead of reading as the missing key it is. It
        // is dropped, and the preparation below says what is missing.
        if let existing = backgroundEngines[id] {
            let usable = descriptor.isCloud ? await existing.isReady : true
            if usable {
                touchResidentBackgroundEngine(descriptor)
                return existing
            }
            if backgroundEngines[id] === existing { backgroundEngines[id] = nil }
        }

        guard await prepareModel(id: id) != nil else { return nil }

        // `prepareModel` also drops its result into dictation's own pool as a
        // side effect of ensuring the download. When this isn't the active
        // dictation model, that's dead weight sitting in a 2-slot cache sized
        // for dictation's own needs — left in place, it can evict the model
        // dictation actually wants warm the next time it transcribes.
        if id != activeModelId {
            engines[id] = nil
            residentLocalEngines.removeAll { $0 == id }
        }

        let engine = makeEngine(for: descriptor)
        do {
            try await engine.prepare(progress: nil)
        } catch {
            AppLog.engine.error("Background engine \(id, privacy: .public) failed to prepare: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        backgroundEngines[id] = engine
        touchResidentBackgroundEngine(descriptor)
        return engine
    }

    /// Awaits an in-flight preparation but gives up if it makes no progress for
    /// `stallTimeoutMs(for:)`. Returns the engine on success, or nil if the
    /// wait timed out — the underlying task is cancelled (best-effort) and left
    /// to be fenced by `evictStalledPreparation`. This is what keeps a stalled
    /// model download from parking the dictation state machine in `.preparing`
    /// (and, via the dedup above, every later attempt with it) until relaunch.
    private func awaitPreparationOrStall(
        _ task: Task<TranscriptionEngine?, Never>,
        id: String
    ) async -> TranscriptionEngine? {
        let gate = TimeoutGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<TranscriptionEngine?, Never>) in
            Task { @MainActor in
                let value = await task.value
                if gate.resolve() { continuation.resume(returning: value) }
            }
            Task { @MainActor in
                var lastFraction = -1.0
                var stalledMs = 0
                while stalledMs < Self.stallTimeoutMs(for: self.readiness[id]) {
                    try? await Task.sleep(for: .milliseconds(Self.prepareStallPollMs))
                    if gate.isResolved { return }
                    let readiness = self.readiness[id]
                    // The load/compile tail (CoreML prewarm) emits no progress
                    // callbacks and can legitimately run for minutes on a cold
                    // machine — don't count it as a stall. Only the metered
                    // download phase has a meaningful "no progress" signal.
                    if Self.isUnmeteredPrepPhase(readiness) {
                        stalledMs = 0
                        continue
                    }
                    let fraction = Self.preparingFraction(of: readiness)
                    if fraction > lastFraction + 0.0001 {
                        lastFraction = fraction
                        stalledMs = 0
                    } else {
                        stalledMs += Self.prepareStallPollMs
                    }
                }
                if gate.resolve() {
                    // The prepare may have completed in the same tick we timed
                    // out — prefer the real engine over a spurious failure.
                    if let ready = self.engines[id], self.readiness[id]?.isInstalled == true {
                        continuation.resume(returning: ready)
                    } else {
                        task.cancel()
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    /// Fences a preparation that stalled out: drops the cached task and bumps
    /// the generation so the still-running task's late writes are ignored, then
    /// surfaces a recoverable failure. No-op once the task has finished
    /// (readiness is no longer `.preparing`).
    private func evictStalledPreparation(id: String, generation: UInt64) {
        guard isCurrentPreparation(id: id, generation: generation) else { return }
        guard case .preparing = readiness[id] else { return }
        preparationTasks[id] = nil
        readiness[id] = .failed("Preparation stalled. Check your connection and try again.")
        _ = nextPreparationGeneration(for: id)
        refreshDownloadedLocalModels()
    }

    /// How long `readiness` may go without progress before it counts as
    /// stalled: `downloadStallTimeoutMs` for the whole fetch — including the
    /// "Connecting…" stretch before the first "Downloading" report, which on a
    /// slow link is where WhisperKit's first 10 MB chunk lands —
    /// `prepareStallTimeoutMs` otherwise.
    private static func stallTimeoutMs(for readiness: ModelReadiness?) -> Int {
        readiness?.isDownloading == true ? downloadStallTimeoutMs : prepareStallTimeoutMs
    }

    private static func preparingFraction(of readiness: ModelReadiness?) -> Double {
        if case .preparing(let fraction, _) = readiness { return fraction }
        // Any non-preparing state means the task finished; report full progress
        // so the stall watchdog doesn't fire while the value path resolves.
        return 1.0
    }

    /// The download phase reports continuous fraction progress, so a stall there
    /// is real. The load/compile phase (CoreML prewarm) is a blocking call that
    /// emits no progress — exempt it from stall detection so a slow cold compile
    /// isn't mistaken for a hang.
    private static func isUnmeteredPrepPhase(_ readiness: ModelReadiness?) -> Bool {
        readiness?.isLoadingOrCompiling ?? false
    }

    func deleteModel(id: String) {
        guard let descriptor = ModelCatalog.model(for: id) else { return }
        if descriptor.isCloud {
            engines[id] = nil
            backgroundEngines[id] = nil
            return
        }
        preparationTasks[id]?.cancel()
        preparationTasks[id] = nil
        _ = nextPreparationGeneration(for: id)
        engines[id] = nil
        residentLocalEngines.removeAll { $0 == id }
        backgroundEngines[id] = nil
        residentBackgroundLocalEngines.removeAll { $0 == id }
        do {
            try ModelStorage.delete(descriptor)
            readiness[id] = .notInstalled
        } catch {
            readiness[id] = .failed("Delete failed: \(error.localizedDescription)")
        }
        refreshDownloadedLocalModels()
    }

    // MARK: - Resident engine cache

    /// Marks a local engine as most-recently-used and drops whatever falls past
    /// `maxResidentLocalEngines`. Dropping the last reference here is what
    /// actually frees the CoreML model — an engine still mid-transcription is
    /// held by its caller and survives until that call returns, so eviction can
    /// never pull the model out from under a running request.
    private func touchResidentEngine(_ descriptor: ModelDescriptor) {
        guard !descriptor.isCloud else { return }
        residentLocalEngines.removeAll { $0 == descriptor.id }
        residentLocalEngines.append(descriptor.id)
        while residentLocalEngines.count > Self.maxResidentLocalEngines {
            let evicted = residentLocalEngines.removeFirst()
            engines[evicted] = nil
            AppLog.engine.info("Released cached engine \(evicted, privacy: .public) to free its model")
        }
    }

    /// `touchResidentEngine` for the background pool: same eviction rules,
    /// its own budget, so a background load never pushes out a dictation model.
    private func touchResidentBackgroundEngine(_ descriptor: ModelDescriptor) {
        guard !descriptor.isCloud else { return }
        residentBackgroundLocalEngines.removeAll { $0 == descriptor.id }
        residentBackgroundLocalEngines.append(descriptor.id)
        while residentBackgroundLocalEngines.count > Self.maxResidentBackgroundLocalEngines {
            let evicted = residentBackgroundLocalEngines.removeFirst()
            backgroundEngines[evicted] = nil
            AppLog.engine.info("Released background engine \(evicted, privacy: .public) to free its model")
        }
    }

    private func makeEngine(for descriptor: ModelDescriptor) -> TranscriptionEngine {
        switch descriptor.backend {
        case .whisperKit:
            return WhisperKitEngine(modelId: descriptor.backendModelId)
        case .fluidAudio:
            return FluidAudioEngine(modelId: descriptor.backendModelId)
        case .openAI:
            return OpenAITranscriptionEngine(modelId: descriptor.backendModelId)
        case .openAIRealtime:
            return OpenAIRealtimeEngine(modelId: descriptor.backendModelId)
        case .elevenLabs:
            return ElevenLabsRealtimeEngine(modelId: descriptor.backendModelId)
        }
    }

    private func nextPreparationGeneration(for id: String) -> UInt64 {
        let next = (preparationGenerations[id] ?? 0) + 1
        preparationGenerations[id] = next
        return next
    }

    private func isCurrentPreparation(id: String, generation: UInt64) -> Bool {
        preparationGenerations[id] == generation
    }
}
