import Foundation
import Observation
import OSLog

/// Drives meeting recording: start/stop capture (mic + system audio) in the
/// background, then transcribe the finished recording in chunks and save it to
/// History. Independent of the dictation hotkey flow — a meeting never pastes
/// anywhere; it's archived for later.
@Observable
@MainActor
final class MeetingController {
    static let shared = MeetingController()

    enum State: Equatable {
        case idle
        case recording
        case transcribing
        /// Importing an uploaded audio/video file: first decode its audio, then
        /// transcribe it. The sub-phase is carried in `importStage`.
        case importing
        case error(String)
    }

    /// Sub-phase of the `.importing` state. Kept out of `State` (and out of the
    /// `.animation(value: state)` the pane uses) so the frequent extraction
    /// progress ticks update the progress bar without re-animating the card.
    enum ImportStage: Equatable {
        case extracting(Double)
        case transcribing
    }

    private(set) var state: State = .idle
    /// Only meaningful while `state == .importing`.
    private(set) var importStage: ImportStage = .extracting(0)
    /// Wall-clock seconds since recording began (drives the timer in the UI).
    private(set) var elapsed: TimeInterval = 0
    /// Live mic+system level, 0…1, for the recording indicator.
    /// Rolling smoothed level history (oldest → newest), driving the same
    /// waveform the dictation HUD shows. The newest sample is the current level.
    private(set) var levelHistory: [Double] = Array(repeating: 0, count: levelHistoryCount)

    static let levelHistoryCount = 140
    private(set) var transcribedChunks = 0
    private(set) var totalChunks = 0
    /// Set briefly after a successful save so the pane can confirm where it went.
    private(set) var lastSavedSummary: String?

    private let recorder = MeetingRecorder()
    private var elapsedTask: Task<Void, Never>?
    private var workingURL: URL?
    /// Held true while a start/stop/cancel is mid-flight across its awaits, so
    /// the three are mutually exclusive even though `state` only flips at
    /// specific points. Mutated only on the main actor.
    private var transitioning = false

    private static let placeholderTranscript = "⚠︎ Audio saved without a transcript."

    private init() {}

    var isBusy: Bool {
        if transitioning { return true }
        switch state {
        case .recording, .transcribing, .importing: return true
        case .idle, .error: return false
        }
    }

    // MARK: - Start

    func start() async {
        guard !isBusy else { return }
        transitioning = true
        defer { transitioning = false }
        lastSavedSummary = nil

        guard await MicPermission.request() else {
            state = .error("Microphone access is required. Enable it in System Settings → Privacy & Security → Microphone.")
            return
        }
        guard ScreenCapturePermission.isGranted || ScreenCapturePermission.request() else {
            state = .error("Screen Recording permission is required to capture other participants' audio. Enable VoiceToText in System Settings → Privacy & Security → Screen Recording, then try again.")
            return
        }

        let url = Self.makeWorkingURL()
        workingURL = url
        recorder.onLevel = { [weak self] level in self?.pushLevel(level) }
        recorder.onStopWithError = { [weak self] error in self?.handleStreamError(error) }

        do {
            try await recorder.start(outputURL: url)
        } catch {
            discardWorkingFile()
            state = .error("Couldn't start recording: \(error.localizedDescription)")
            return
        }

        let start = Date()
        elapsed = 0
        resetLevels()
        state = .recording
        startElapsedTicker(from: start)
        AppLog.audio.info("Meeting recording running")
    }

    // MARK: - Stop & transcribe

    func stop() async {
        guard case .recording = state else { return }
        transitioning = true
        defer { transitioning = false }
        stopElapsedTicker()
        resetLevels()
        // Clear any chunk counts from a prior transcription before showing the
        // card, so the brief stopCapture teardown can't flash a stale "3/3".
        transcribedChunks = 0
        totalChunks = 0
        state = .transcribing

        guard let result = await recorder.stop(), result.duration >= 1.0 else {
            discardWorkingFile()
            state = .error("The conversation was too short to save.")
            return
        }
        // The recorder finalized the file at the same working URL.
        let (issue, summary) = await transcribeAndArchive(url: result.url, duration: result.duration)
        workingURL = nil
        finish(issue: issue, summary: summary)
    }

    // MARK: - Import a file

    /// Transcribes an uploaded audio or video file and archives it to History as
    /// a conversation. Decodes the file's audio into a working WAV first (so a
    /// video is treated exactly like a recorded conversation), then runs the same
    /// transcribe-and-save path as `stop()`.
    func importMedia(url: URL) async {
        guard !isBusy else { return }
        transitioning = true
        defer { transitioning = false }
        lastSavedSummary = nil

        let working = Self.makeWorkingURL()
        workingURL = working
        importStage = .extracting(0)
        state = .importing

        do {
            try await AudioFileExtractor.extractToWAV(
                source: url,
                destination: working,
                onProgress: { fraction in
                    Task { @MainActor [weak self] in
                        // Ignore a late progress hop that lands after we've moved
                        // on to the transcribe stage (or finished entirely).
                        guard let self,
                              case .importing = self.state,
                              case .extracting = self.importStage else { return }
                        self.importStage = .extracting(fraction)
                    }
                }
            )
        } catch {
            discardWorkingFile()
            state = .error(error.localizedDescription)
            return
        }

        let duration = Self.wavDuration(at: working)
        guard duration >= 1.0 else {
            discardWorkingFile()
            state = .error("That file was too short to transcribe.")
            return
        }

        importStage = .transcribing
        let (issue, summary) = await transcribeAndArchive(url: working, duration: duration)
        workingURL = nil
        finish(issue: issue, summary: summary)
    }

    // MARK: - Transcribe & archive (shared by stop & import)

    /// Transcribes the WAV at `url` with the active model and files it into
    /// History as a conversation. Never throws — on any failure the audio is
    /// still archived (with a placeholder/notice) so a long recording is never
    /// lost over a transcription hiccup. Returns a user-facing `issue` message
    /// (nil = clean) and a success `summary`. Drives `transcribedChunks` /
    /// `totalChunks` as it goes.
    private func transcribeAndArchive(url: URL, duration: Double) async -> (issue: String?, summary: String?) {
        transcribedChunks = 0
        totalChunks = 0

        let transcript: String
        let model: ModelDescriptor?
        var issue: String?
        if let descriptor = ModelRegistry.shared.activeModel,
           let engine = await ModelRegistry.shared.prepareModel(id: descriptor.id) {
            model = descriptor
            do {
                let text = try await MeetingTranscriber.transcribe(
                    url: url,
                    engine: engine,
                    onProgress: { [weak self] done, total in
                        self?.transcribedChunks = done
                        self?.totalChunks = total
                    }
                )
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    transcript = "(No speech detected.)"
                    issue = "No speech was detected, but the audio was saved to History."
                } else {
                    transcript = text
                }
            } catch {
                transcript = Self.placeholderTranscript
                issue = "Transcription failed (\(error.localizedDescription)). The audio was saved to History."
            }
        } else {
            model = nil
            transcript = Self.placeholderTranscript
            issue = "No transcription model was ready, but the audio was saved to History."
        }

        saveToHistory(url: url, transcript: transcript, duration: duration, model: model)
        let summary = issue == nil ? "Saved a \(duration.formattedClock) recording to History." : nil
        return (issue, summary)
    }

    /// Settles the state machine after a stop or import finishes.
    private func finish(issue: String?, summary: String?) {
        if let issue {
            state = .error(issue)
        } else {
            lastSavedSummary = summary
            state = .idle
        }
    }

    private func saveToHistory(url: URL, transcript: String, duration: Double, model: ModelDescriptor?) {
        RecordingHistoryStore.shared.ingest(
            fileURL: url,
            transcript: transcript,
            durationSeconds: duration,
            model: model,
            source: .meeting
        )
    }

    /// Duration of a finalized mono 16-bit WAV from its byte length — avoids
    /// re-decoding just to learn how long the extracted audio is.
    private static func wavDuration(at url: URL) -> Double {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let sampleBytes = max(0, size - WAVEncoder.headerSize)
        return Double(sampleBytes / 2) / AudioConfig.targetSampleRate
    }

    // MARK: - Cancel / errors

    func cancel() async {
        guard case .recording = state, !transitioning else { return }
        transitioning = true
        defer { transitioning = false }
        stopElapsedTicker()
        // Flip out of .recording synchronously, before the await, so a racing
        // stop() sees a non-.recording state and bails — no spurious "too short
        // to save" error and no concurrent recorder teardown.
        resetLevels()
        elapsed = 0
        state = .idle
        await recorder.cancel()
        discardWorkingFile()
        AppLog.audio.info("Meeting recording cancelled")
    }

    func dismissError() {
        if case .error = state { state = .idle }
    }

    private func handleStreamError(_ error: Error) {
        guard case .recording = state else { return }
        stopElapsedTicker()
        resetLevels()
        state = .error("Recording stopped: \(error.localizedDescription)")
        // Tear the recorder down off the hot path; keep `transitioning` set so a
        // new start() can't race the teardown on the shared recorder.
        transitioning = true
        Task { @MainActor in
            await recorder.cancel()
            discardWorkingFile()
            transitioning = false
        }
    }

    // MARK: - Helpers

    private func discardWorkingFile() {
        if let url = workingURL { try? FileManager.default.removeItem(at: url) }
        workingURL = nil
    }

    /// Smooths the incoming level the same way the dictation HUD does and pushes
    /// it onto the rolling history that drives the waveform.
    private func pushLevel(_ level: Double) {
        let smoothed = (levelHistory.last ?? 0) * 0.6 + level * 0.4
        var history = levelHistory
        history.removeFirst()
        history.append(smoothed)
        levelHistory = history
    }

    private func resetLevels() {
        levelHistory = Array(repeating: 0, count: Self.levelHistoryCount)
    }

    private func startElapsedTicker(from start: Date) {
        elapsedTask?.cancel()
        elapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .recording else { return }
                self.elapsed = Date().timeIntervalSince(start)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopElapsedTicker() {
        elapsedTask?.cancel()
        elapsedTask = nil
    }

    private static var meetingsTempDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceToText/MeetingsTemp", isDirectory: true)
    }

    private static func makeWorkingURL() -> URL {
        let dir = meetingsTempDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(UUID().uuidString).wav", isDirectory: false)
    }

    /// Reclaims meeting recordings stranded in the temp directory by a crash,
    /// force quit, or power loss (mid-recording or mid-transcribe). Repairs the
    /// WAV header from the bytes on disk and files the audio into History with a
    /// recovery note so the recording survives; deletes anything too short to
    /// matter. Call once at launch. Without it, an interrupted meeting is both
    /// lost (header still says 0 bytes) and leaked (never reclaimed).
    static func recoverOrphanedTempFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: meetingsTempDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return }
        for url in files where url.pathExtension == "wav" {
            let repaired = StreamingWAVWriter.repairHeaderInPlace(at: url)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let duration = Double(max(0, size - 44) / 2) / AudioConfig.targetSampleRate
            if repaired, duration >= 1.0 {
                RecordingHistoryStore.shared.ingest(
                    fileURL: url,
                    transcript: "⚠︎ Recovered recording — the app quit before transcription finished. Audio saved without a transcript.",
                    durationSeconds: duration,
                    model: nil,
                    source: .meeting
                )
            } else {
                try? fm.removeItem(at: url)
            }
        }
    }
}
