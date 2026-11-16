import AVFoundation
import Foundation
import Observation

@Observable
final class Importer {
    static let shared = Importer()

    private(set) var fraction: Double?
    private(set) var fileName: String?
    var failure: String?

    var isImporting: Bool { fraction != nil }

    private init() {}

    func importFile(_ source: URL) async {
        guard !isImporting else { return }
        fraction = 0
        fileName = source.lastPathComponent
        defer {
            fraction = nil
            fileName = nil
        }

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let destination = Library.newAudioURL(id: id)
        do {
            try await AudioFileExtractor.extractToWAV(source: source, destination: destination) { value in
                Task { @MainActor in
                    guard Importer.shared.isImporting else { return }
                    Importer.shared.fraction = value
                }
            }
            let file = try AVAudioFile(forReading: destination)
            let duration = Double(file.length) / file.fileFormat.sampleRate
            guard duration > 0 else {
                try? FileManager.default.removeItem(at: destination)
                failure = "\(source.lastPathComponent) has no audio to transcribe."
                return
            }
            Library.shared.addPending(id: id, durationSeconds: duration)
            Transcriber.shared.enqueue(id)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
