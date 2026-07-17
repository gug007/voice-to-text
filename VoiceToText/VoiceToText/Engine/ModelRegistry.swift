import Foundation
import Observation

enum CloudProvider: String, Sendable, Hashable {
    case openAI
    case elevenLabs

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .elevenLabs: return "ElevenLabs"
        }
    }
}

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
    let notes: String
    /// 1...10 subjective rating surfaced in the Models list.
    let quality: Int
    let speed: Int
    /// Measured word error rate for LOCAL models, from the Hugging Face Open ASR
    /// Leaderboard English average (mid-2026). `nil` for cloud models, which have
    /// no comparable public leaderboard, and keep their curated `quality` rating.
    let benchmarkWER: Double?

    var isCloud: Bool { backend.isCloud }
    var isRealtime: Bool { backend.isStreaming }
}

enum ModelCatalog {
    static let all: [ModelDescriptor] = [
        ModelDescriptor(
            id: "parakeet-tdt-v3",
            displayName: "Parakeet TDT v3",
            backend: .fluidAudio,
            backendModelId: "parakeet-tdt-v3",
            approxSizeMB: 470,
            languages: "25 European + JA",
            notes: "Fastest on your Mac. Best for English and major European languages.",
            quality: 9,
            speed: 10,
            benchmarkWER: 6.32
        ),
        ModelDescriptor(
            id: "whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo",
            backend: .whisperKit,
            backendModelId: "openai_whisper-large-v3-v20240930_turbo",
            approxSizeMB: 632,
            languages: "99",
            notes: "Excellent accuracy in 99 languages. A great all-rounder.",
            quality: 8,
            speed: 7,
            benchmarkWER: 7.75
        ),
        ModelDescriptor(
            id: "whisper-large-v3",
            displayName: "Whisper Large v3",
            backend: .whisperKit,
            backendModelId: "openai_whisper-large-v3-v20240930",
            approxSizeMB: 626,
            languages: "99",
            notes: "Extremely accurate offline. Noticeably slower than Turbo.",
            quality: 8,
            speed: 3,
            benchmarkWER: 7.44
        ),
        ModelDescriptor(
            id: "whisper-small",
            displayName: "Whisper Small",
            backend: .whisperKit,
            backendModelId: "openai_whisper-small",
            approxSizeMB: 244,
            languages: "99",
            notes: "Smaller and faster, but makes more mistakes.",
            quality: 5,
            speed: 8,
            benchmarkWER: 8.59
        ),
        ModelDescriptor(
            id: "whisper-base",
            displayName: "Whisper Base",
            backend: .whisperKit,
            backendModelId: "openai_whisper-base",
            approxSizeMB: 77,
            languages: "99",
            notes: "Very small. Quite a few mistakes — only worth it on slow Macs.",
            quality: 3,
            speed: 9,
            benchmarkWER: 10.32
        ),
        ModelDescriptor(
            id: "whisper-tiny",
            displayName: "Whisper Tiny",
            backend: .whisperKit,
            backendModelId: "openai_whisper-tiny",
            approxSizeMB: 39,
            languages: "99",
            notes: "Smallest. Lots of mistakes — mainly useful for testing.",
            quality: 2,
            speed: 10,
            benchmarkWER: 12.81
        ),
        ModelDescriptor(
            id: "elevenlabs-scribe-v2-realtime",
            displayName: "Scribe v2 Realtime (ElevenLabs)",
            backend: .elevenLabs,
            backendModelId: "scribe_v2_realtime",
            approxSizeMB: 0,
            languages: "90+",
            notes: "Live streaming — words appear as you speak. Audio goes to ElevenLabs.",
            quality: 9,
            speed: 10,
            benchmarkWER: nil
        ),
        ModelDescriptor(
            id: "openai-gpt-realtime-whisper",
            displayName: "GPT Realtime Whisper (OpenAI)",
            backend: .openAIRealtime,
            backendModelId: "gpt-realtime-whisper",
            approxSizeMB: 0,
            languages: "99+",
            notes: "OpenAI's newest live streaming model, built for the lowest latency. Audio goes to OpenAI.",
            quality: 9,
            speed: 10,
            benchmarkWER: nil
        ),
        ModelDescriptor(
            id: "openai-gpt-4o-transcribe-realtime",
            displayName: "GPT-4o Transcribe Realtime (OpenAI)",
            backend: .openAIRealtime,
            backendModelId: "gpt-4o-transcribe",
            approxSizeMB: 0,
            languages: "99+",
            notes: "Live streaming — words appear as you speak. Audio goes to OpenAI.",
            quality: 9,
            speed: 9,
            benchmarkWER: nil
        ),
        ModelDescriptor(
            id: "openai-gpt-4o-transcribe",
            displayName: "GPT-4o Transcribe (OpenAI)",
            backend: .openAI,
            backendModelId: "gpt-4o-transcribe",
            approxSizeMB: 0,
            languages: "99+",
            notes: "The most accurate option overall. Audio goes to OpenAI.",
            quality: 10,
            speed: 5,
            benchmarkWER: nil
        ),
        ModelDescriptor(
            id: "openai-gpt-4o-transcribe-diarize",
            displayName: "GPT-4o Transcribe Diarize (OpenAI)",
            backend: .openAI,
            backendModelId: "gpt-4o-transcribe-diarize",
            approxSizeMB: 0,
            languages: "99+",
            notes: "Labels who said what — best for meetings. Audio goes to OpenAI.",
            quality: 10,
            speed: 4,
            benchmarkWER: nil
        ),
        ModelDescriptor(
            id: "openai-gpt-4o-mini-transcribe",
            displayName: "GPT-4o Mini Transcribe (OpenAI)",
            backend: .openAI,
            backendModelId: "gpt-4o-mini-transcribe",
            approxSizeMB: 0,
            languages: "99+",
            notes: "Nearly as accurate as GPT-4o Transcribe and cheaper to run.",
            quality: 9,
            speed: 7,
            benchmarkWER: nil
        ),
        ModelDescriptor(
            id: "openai-whisper-1",
            displayName: "Whisper-1 (OpenAI)",
            backend: .openAI,
            backendModelId: "whisper-1",
            approxSizeMB: 0,
            languages: "99",
            notes: "OpenAI's older online model. Cheapest, but less accurate than GPT-4o.",
            quality: 8,
            speed: 6,
            benchmarkWER: nil
        ),
    ]

    static func model(for id: String) -> ModelDescriptor? {
        all.first { $0.id == id }
    }
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

    @ObservationIgnored
    private var engines: [String: TranscriptionEngine] = [:]

    @ObservationIgnored
    private var preparationTasks: [String: Task<TranscriptionEngine?, Never>] = [:]

    @ObservationIgnored
    private var preparationGenerations: [String: UInt64] = [:]

    /// `prepare()` (HuggingFace download, CoreML compile) has no internal
    /// timeout, so a stalled network read parks the caller forever. Treat a
    /// preparation that makes no progress for this long as stuck.
    private static let prepareStallTimeoutMs = 120_000
    private static let prepareStallPollMs = 1_000

    private init() {
        self.activeModelId = UserDefaults.standard.string(forKey: Keys.activeModelId)
            ?? "parakeet-tdt-v3"
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
    /// back), otherwise the dictation model.
    var conversationModel: ModelDescriptor? {
        if let id = conversationModelId, let explicit = ModelCatalog.model(for: id) {
            return explicit
        }
        return activeModel
    }

    func setActive(_ modelId: String) {
        guard ModelCatalog.model(for: modelId) != nil else { return }
        activeModelId = modelId
        UserDefaults.standard.set(modelId, forKey: Keys.activeModelId)
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

    @discardableResult
    func prepareModel(id: String) async -> TranscriptionEngine? {
        guard let descriptor = ModelCatalog.model(for: id) else { return nil }

        if let existing = engines[id], readiness[id]?.isInstalled == true {
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
                self.readiness[id] = .installed(sizeBytes: ModelStorage.diskUsageBytes(descriptor))
                return engine
            } catch {
                guard self.isCurrentPreparation(id: id, generation: generation),
                      !Task.isCancelled else { return nil }
                self.readiness[id] = .failed(error.localizedDescription)
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

    /// Awaits an in-flight preparation but gives up if it makes no progress for
    /// `prepareStallTimeoutMs`. Returns the engine on success, or nil if the
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
                while stalledMs < Self.prepareStallTimeoutMs {
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
        guard case .preparing(_, let message) = readiness else { return false }
        let lower = message.lowercased()
        return lower.contains("load") || lower.contains("compil")
    }

    func deleteModel(id: String) {
        guard let descriptor = ModelCatalog.model(for: id) else { return }
        if descriptor.isCloud {
            engines[id] = nil
            return
        }
        preparationTasks[id]?.cancel()
        preparationTasks[id] = nil
        _ = nextPreparationGeneration(for: id)
        engines[id] = nil
        do {
            try ModelStorage.delete(descriptor)
            readiness[id] = .notInstalled
        } catch {
            readiness[id] = .failed("Delete failed: \(error.localizedDescription)")
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

/// One-shot resolution gate so a value/timeout race resumes its continuation
/// exactly once. Both racers may run on the same actor, but the lock keeps it
/// correct regardless of scheduling.
private final class TimeoutGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false

    var isResolved: Bool {
        lock.lock(); defer { lock.unlock() }
        return resolved
    }

    func resolve() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if resolved { return false }
        resolved = true
        return true
    }
}
