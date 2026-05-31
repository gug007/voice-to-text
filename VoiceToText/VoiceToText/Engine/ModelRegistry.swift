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
        case elevenLabs

        var cloudProvider: CloudProvider? {
            switch self {
            case .whisperKit, .fluidAudio: return nil
            case .openAI: return .openAI
            case .elevenLabs: return .elevenLabs
            }
        }

        var isCloud: Bool { cloudProvider != nil }
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

    var isCloud: Bool { backend.isCloud }
}

enum ModelCatalog {
    static let all: [ModelDescriptor] = [
        ModelDescriptor(
            id: "elevenlabs-scribe-v2-realtime",
            displayName: "Scribe v2 Realtime (ElevenLabs)",
            backend: .elevenLabs,
            backendModelId: "scribe_v2_realtime",
            approxSizeMB: 0,
            languages: "90+",
            notes: "Live streaming — words appear as you speak. Audio goes to ElevenLabs.",
            quality: 9,
            speed: 10
        ),
        ModelDescriptor(
            id: "parakeet-tdt-v3",
            displayName: "Parakeet TDT v3",
            backend: .fluidAudio,
            backendModelId: "parakeet-tdt-v3",
            approxSizeMB: 470,
            languages: "25 European + JA",
            notes: "Fastest on your Mac. Best for English and major European languages.",
            quality: 8,
            speed: 10
        ),
        ModelDescriptor(
            id: "whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo",
            backend: .whisperKit,
            backendModelId: "openai_whisper-large-v3-v20240930_turbo",
            approxSizeMB: 632,
            languages: "99",
            notes: "Excellent accuracy in 99 languages. A great all-rounder.",
            quality: 9,
            speed: 7
        ),
        ModelDescriptor(
            id: "whisper-large-v3",
            displayName: "Whisper Large v3",
            backend: .whisperKit,
            backendModelId: "openai_whisper-large-v3-v20240930",
            approxSizeMB: 626,
            languages: "99",
            notes: "Most accurate offline option. Noticeably slower than Turbo.",
            quality: 10,
            speed: 3
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
            speed: 8
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
            speed: 9
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
            speed: 10
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
            speed: 5
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
            speed: 7
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
            speed: 6
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
    }

    static let shared = ModelRegistry()

    private(set) var activeModelId: String
    private(set) var readiness: [String: ModelReadiness] = [:]

    @ObservationIgnored
    private var engines: [String: TranscriptionEngine] = [:]

    @ObservationIgnored
    private var preparationTasks: [String: Task<TranscriptionEngine?, Never>] = [:]

    @ObservationIgnored
    private var preparationGenerations: [String: UInt64] = [:]

    private init() {
        self.activeModelId = UserDefaults.standard.string(forKey: Keys.activeModelId)
            ?? "parakeet-tdt-v3"
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

    func setActive(_ modelId: String) {
        guard ModelCatalog.model(for: modelId) != nil else { return }
        activeModelId = modelId
        UserDefaults.standard.set(modelId, forKey: Keys.activeModelId)
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
            return await existingTask.value
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
        let prepared = await task.value
        if isCurrentPreparation(id: id, generation: generation) {
            preparationTasks[id] = nil
        }
        return prepared
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
