import Foundation
import Observation

struct ModelDescriptor: Identifiable, Hashable, Sendable {
    enum Backend: String, Sendable, Hashable {
        case whisperKit
        case fluidAudio
    }

    let id: String
    let displayName: String
    let backend: Backend
    let backendModelId: String
    let approxSizeMB: Int
    let languages: String
    let recommended: Bool
    let notes: String
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
            recommended: true,
            notes: "Fastest. Runs on the Apple Neural Engine."
        ),
        ModelDescriptor(
            id: "whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo",
            backend: .whisperKit,
            backendModelId: "openai_whisper-large-v3-v20240930_turbo",
            approxSizeMB: 632,
            languages: "99",
            recommended: true,
            notes: "Best multilingual. 6× faster than Large v3 with near-equal accuracy."
        ),
        ModelDescriptor(
            id: "whisper-large-v3",
            displayName: "Whisper Large v3",
            backend: .whisperKit,
            backendModelId: "openai_whisper-large-v3-v20240930",
            approxSizeMB: 626,
            languages: "99",
            recommended: false,
            notes: "Highest accuracy. Slower than Turbo."
        ),
        ModelDescriptor(
            id: "whisper-small",
            displayName: "Whisper Small",
            backend: .whisperKit,
            backendModelId: "openai_whisper-small",
            approxSizeMB: 244,
            languages: "99",
            recommended: false,
            notes: "Lightweight multilingual option."
        ),
        ModelDescriptor(
            id: "whisper-base",
            displayName: "Whisper Base",
            backend: .whisperKit,
            backendModelId: "openai_whisper-base",
            approxSizeMB: 77,
            languages: "99",
            recommended: false,
            notes: "Very small. Limited accuracy."
        ),
        ModelDescriptor(
            id: "whisper-tiny",
            displayName: "Whisper Tiny",
            backend: .whisperKit,
            backendModelId: "openai_whisper-tiny",
            approxSizeMB: 39,
            languages: "99",
            recommended: false,
            notes: "Smallest. Lowest accuracy."
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

    private init() {
        self.activeModelId = UserDefaults.standard.string(forKey: Keys.activeModelId)
            ?? "parakeet-tdt-v3"
        refreshInstalledState()
    }

    /// Kick off a background download of the active model if it isn't already
    /// installed or being prepared. Safe to call multiple times — no-ops when
    /// the model is already present or a download is in flight.
    func bootstrapActiveModelIfNeeded() {
        let id = activeModelId
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
            if ModelStorage.isInstalled(model) {
                readiness[model.id] = .installed(sizeBytes: ModelStorage.diskUsageBytes(model))
            } else {
                readiness[model.id] = .notInstalled
            }
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

        readiness[id] = .preparing(fraction: 0.0, message: "Starting…")
        let engine = makeEngine(for: descriptor)
        do {
            try await engine.prepare { [weak self] fraction, message in
                Task { @MainActor in
                    guard let self else { return }
                    self.readiness[id] = .preparing(fraction: fraction, message: message)
                }
            }
            engines[id] = engine
            readiness[id] = .installed(sizeBytes: ModelStorage.diskUsageBytes(descriptor))
            return engine
        } catch {
            readiness[id] = .failed(error.localizedDescription)
            return nil
        }
    }

    func deleteModel(id: String) {
        guard let descriptor = ModelCatalog.model(for: id) else { return }
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
        }
    }
}
