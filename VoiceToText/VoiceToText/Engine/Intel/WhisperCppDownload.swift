#if arch(x86_64)
import CryptoKit
import Foundation

/// Fetches a `WhisperCppModel` file into its folder.
///
/// The file downloads outside the model folder, is checked against its size
/// and SHA-256, and only then moves in, with a rename on the same volume. So a
/// download that is cancelled, drops or fails its check never leaves part of a
/// file where `ModelStorage` would count the model as installed.
nonisolated enum WhisperCppDownload {
    enum Failure: LocalizedError {
        case httpStatus(Int)
        case wrongSize(fileName: String, expected: Int64, actual: Int64)
        case wrongChecksum(fileName: String)

        var errorDescription: String? {
            switch self {
            case .httpStatus(let status):
                return "Hugging Face answered with HTTP \(status)."
            case .wrongSize(let fileName, let expected, let actual):
                return "\(fileName) downloaded as \(actual) bytes instead of \(expected). Try again."
            case .wrongChecksum(let fileName):
                return "\(fileName) didn't match its checksum. Try again."
            }
        }
    }

    /// How often the download reports progress. Often enough that the
    /// registry's stall watchdog sees a healthy download move, rare enough not
    /// to flood the main actor with readiness updates.
    static let progressInterval: TimeInterval = 0.25

    /// Downloads `model`, reporting 0–1 by bytes with "Downloading…" messages
    /// (the phase `ModelReadiness.isDownloading` reads). Cancelling the
    /// calling task cancels the transfer, and the call throws.
    static func fetch(_ model: WhisperCppModel, progress: PrepareProgress?) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: WhisperCppModel.baseURL, withIntermediateDirectories: true)
        // A temporary folder on the model folder's volume, so the last move is
        // a rename.
        let staging = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: WhisperCppModel.baseURL,
            create: true
        )
        defer { try? fileManager.removeItem(at: staging) }

        let reporter = ProgressReporter(totalBytes: model.byteCount, progress: progress)
        let poller = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(progressInterval))
                reporter.reportIfMoved()
            }
        }
        defer { poller.cancel() }
        let (downloaded, response) = try await URLSession.shared.download(
            for: URLRequest(url: model.downloadURL),
            delegate: reporter
        )
        reporter.reportIfMoved()
        let staged = staging.appendingPathComponent(model.fileName, isDirectory: false)
        try fileManager.moveItem(at: downloaded, to: staged)
        try Task.checkCancellation()

        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw Failure.httpStatus(status)
        }
        let size = (try fileManager.attributesOfItem(atPath: staged.path)[.size] as? NSNumber)?.int64Value ?? -1
        guard size == model.byteCount else {
            throw Failure.wrongSize(fileName: model.fileName, expected: model.byteCount, actual: size)
        }
        guard try sha256Hex(of: staged) == model.sha256 else {
            throw Failure.wrongChecksum(fileName: model.fileName)
        }

        try fileManager.createDirectory(at: model.folder, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: model.fileURL.path) {
            try fileManager.removeItem(at: model.fileURL)
        }
        try fileManager.moveItem(at: staged, to: model.fileURL)
    }

    /// Streamed, so a gigabyte file never sits in memory whole.
    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try autoreleasepool { try handle.read(upToCount: 4 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Turns the download task's byte count into the app's progress reports,
    /// read every `progressInterval`. `URLSession.download(for:delegate:)`
    /// sends its delegate no `didWriteData`, and the task's `Progress` only
    /// moved at the end, so the count is polled. A report goes out only when
    /// it has moved, which leaves a stalled download for the registry's
    /// watchdog to see. The task holds this delegate only until it completes.
    private final class ProgressReporter: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let totalBytes: Int64
        private let progress: PrepareProgress?
        private let lock = NSLock()
        private var task: URLSessionTask?
        private var reportedBytes: Int64 = -1

        init(totalBytes: Int64, progress: PrepareProgress?) {
            self.totalBytes = totalBytes
            self.progress = progress
        }

        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            lock.withLock { self.task = task }
        }

        func reportIfMoved() {
            let received = lock.withLock { () -> Int64? in
                guard let bytes = task?.countOfBytesReceived, bytes != reportedBytes else { return nil }
                reportedBytes = bytes
                return bytes
            }
            guard let received, let progress else { return }
            let fraction = min(max(Double(received) / Double(max(totalBytes, 1)), 0), 1)
            progress(fraction, "Downloading \(received / 1_000_000) of \(totalBytes / 1_000_000) MB")
        }
    }
}
#endif
