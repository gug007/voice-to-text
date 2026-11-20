import FluidAudio
import Foundation
import Observation
import UIKit

@Observable
final class Transcriber {
    static let shared = Transcriber()

    enum ModelState: Equatable {
        case missing
        case preparing(fraction: Double, message: String)
        case ready
        case failed(String)
    }

    struct Progress: Equatable {
        let done: Int
        let total: Int
        var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
    }

    private(set) var modelState: ModelState
    private(set) var activeID: UUID?
    private(set) var progress: Progress?
    private(set) var queue: [UUID] = []

    static let approxDownloadMB = 470

    private let engine = FluidAudioEngine()
    private var prepareTask: Task<Void, Never>?
    private var isDraining = false

    static var isModelDownloaded: Bool {
        ParakeetModelFiles.hasRequiredModels(in: AsrModels.defaultCacheDirectory())
    }

    private init() {
        modelState = .missing
    }

    func isWaiting(_ id: UUID) -> Bool {
        queue.contains(id) || activeID == id
    }

    func resumePendingWork() {
        for entry in Library.shared.entries.reversed() where entry.needsTranscript && !entry.isSavedForLater {
            enqueue(entry.id)
        }
    }

    func enqueue(_ id: UUID) {
        guard !isWaiting(id) else { return }
        Library.shared.update(id: id) { $0.isSavedForLater ? $0.updatingStatus(Library.waitingStatus) : nil }
        queue.append(id)
        if modelState == .ready {
            drain()
        } else if Self.isModelDownloaded {
            prepareModel()
        }
    }

    func forget(_ id: UUID) {
        queue.removeAll { $0 == id }
    }

    func prepareModel() {
        if case .preparing = modelState { return }
        guard modelState != .ready else { return }
        let downloaded = Self.isModelDownloaded
        modelState = .preparing(fraction: 0, message: downloaded ? "Loading model…" : "Starting…")
        prepareTask = Task {
            let background = UIApplication.shared.beginBackgroundTask(withName: "model")
            defer { UIApplication.shared.endBackgroundTask(background) }
            do {
                try await engine.prepare { fraction, message in
                    Task { @MainActor in
                        guard case .preparing = Transcriber.shared.modelState else { return }
                        Transcriber.shared.modelState = .preparing(fraction: fraction, message: message)
                    }
                }
                modelState = .ready
                drain()
            } catch {
                modelState = .failed(Self.describe(error))
            }
        }
    }

    func deleteModel() {
        guard activeID == nil else { return }
        if case .preparing = modelState { return }
        try? FileManager.default.removeItem(at: AsrModels.defaultCacheDirectory())
        modelState = .missing
    }

    private func drain() {
        guard !isDraining, modelState == .ready else { return }
        isDraining = true
        Task {
            let background = UIApplication.shared.beginBackgroundTask(withName: "transcribe")
            defer {
                UIApplication.shared.endBackgroundTask(background)
                isDraining = false
            }
            while let id = queue.first {
                queue.removeFirst()
                await transcribe(id)
            }
        }
    }

    private func transcribe(_ id: UUID) async {
        let library = Library.shared
        guard let entry = library.entry(id: id), entry.needsTranscript else { return }
        activeID = id
        progress = nil
        defer {
            activeID = nil
            progress = nil
        }
        do {
            let text = try await MeetingTranscriber.transcribe(
                url: library.audioURL(for: entry),
                engine: engine,
                corrections: []
            ) { done, total in
                Transcriber.shared.progress = Progress(done: done, total: total)
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                library.update(id: id) {
                    $0.updatingStatus(.init(kind: .failed, message: "No speech was found in this recording."))
                }
                return
            }
            library.update(id: id) {
                $0.resolvingPlaceholder(transcript: trimmed, modelId: Library.modelId, modelName: Library.modelName)
            }
        } catch {
            library.update(id: id) {
                $0.updatingStatus(.init(kind: .failed, message: Self.describe(error)))
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
