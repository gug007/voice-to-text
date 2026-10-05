import Foundation

/// Explains a conversation that ended without the user pressing Stop — the
/// system tearing the capture stream down, or the recording failing to reach
/// the disk — and decides whether what was captured is worth saving.
///
/// Foundation-only and `nonisolated` (it deliberately doesn't import
/// ScreenCaptureKit) so the harness compiles it standalone; the stream errors
/// are matched by their NSError domain and code instead.
nonisolated enum MeetingInterruption {
    /// `SCStreamErrorDomain`'s value, spelled out to avoid the framework import.
    static let streamErrorDomain = "com.apple.ScreenCaptureKit.SCStreamErrorDomain"

    /// The `SCStreamError.Code` raw values we explain, from SCError.h.
    enum StreamCode {
        static let userDeclined = -3801
        static let connectionInvalid = -3804
        static let connectionInterrupted = -3805
        static let noDisplayList = -3814
        static let noCaptureSource = -3815
        static let userStopped = -3817
        static let systemStoppedStream = -3821
        static let insufficientStorage = -3822
    }

    /// Anything shorter isn't a recording anyone wants back — the same bar a
    /// normal Stop has always used.
    static let minimumSalvageSeconds: Double = 1.0

    static func shouldSalvage(capturedSeconds: Double) -> Bool {
        capturedSeconds >= minimumSalvageSeconds
    }

    /// A lowercase clause saying why the recording stopped, written to follow
    /// "Recording stopped at 12:05 — ". Unknown errors fall back to their own
    /// description, which is still better than a code.
    static func reason(for error: Error) -> String {
        if isOutOfSpace(error) { return "your Mac ran out of disk space" }
        if case MeetingRecorderError.diskWriteFailed = error {
            return "the recording couldn't be written to disk"
        }
        let nsError = error as NSError
        if nsError.domain == streamErrorDomain {
            switch nsError.code {
            case StreamCode.userStopped:
                return "capture was stopped from the macOS screen-sharing indicator"
            case StreamCode.systemStoppedStream:
                return "macOS stopped the audio capture"
            case StreamCode.noCaptureSource, StreamCode.noDisplayList:
                return "the display it was capturing from was disconnected"
            case StreamCode.userDeclined:
                return "Screen Recording permission was turned off"
            case StreamCode.connectionInvalid, StreamCode.connectionInterrupted:
                return "macOS's screen capture service stopped unexpectedly"
            default:
                break
            }
        }
        return trimmedDescription(of: error)
    }

    /// The error card's text after an interrupted conversation. Leads with when
    /// and why it stopped, then says whether anything survived and — because
    /// the card is the only feedback — what went wrong transcribing it.
    static func message(
        for interruption: Error,
        capturedSeconds: Double,
        transcriptionIssue: MeetingTranscriptionIssue?
    ) -> String {
        let reason = reason(for: interruption)
        guard shouldSalvage(capturedSeconds: capturedSeconds) else {
            return "Recording stopped — \(reason). Nothing was captured."
        }
        var text = "Recording stopped at \(clock(capturedSeconds)) — \(reason). Everything up to then was saved to History"
        text += transcriptionIssue.map { ", but " + $0.clause } ?? "."
        // History's index is rewritten on the same full disk, and that write can
        // fail too — the transcript only sticks once a later write gets through.
        if isOutOfSpace(interruption) {
            text += " Free up some disk space so VoiceToText can finish saving it."
        }
        return text
    }

    /// The card when the file holds audio but couldn't be finalized — the disk
    /// failing again as it closed. The file stays in MeetingsTemp, where
    /// launch-time recovery repairs its header and files it into History.
    /// `interruption` is nil when the user pressed Stop.
    static func unfinishedMessage(interruption: Error?, capturedSeconds: Double) -> String {
        let setAside = "couldn't be finished writing to disk, so it was set aside. VoiceToText will try to recover it to History the next time it opens."
        guard let interruption else {
            return "The \(clock(capturedSeconds)) recording \(setAside)"
        }
        return "Recording stopped at \(clock(capturedSeconds)) — \(reason(for: interruption)). The recording \(setAside)"
    }

    // MARK: - Helpers

    /// A full disk, whether the WAV writer hit it or ScreenCaptureKit did.
    /// FileHandle reports ENOSPC wrapped in a Cocoa write error, so look one
    /// level down as well as at the error itself.
    private static func isOutOfSpace(_ error: Error) -> Bool {
        if case MeetingRecorderError.diskWriteFailed(let underlying) = error {
            return isOutOfSpace(underlying)
        }
        let nsError = error as NSError
        if nsError.domain == streamErrorDomain {
            return nsError.code == StreamCode.insufficientStorage
        }
        let candidates = [nsError] + [nsError.userInfo[NSUnderlyingErrorKey] as? NSError].compactMap { $0 }
        return candidates.contains { candidate in
            (candidate.domain == NSCocoaErrorDomain && candidate.code == NSFileWriteOutOfSpaceError)
                || (candidate.domain == NSPOSIXErrorDomain
                    && (candidate.code == Int(ENOSPC) || candidate.code == Int(EDQUOT)))
        }
    }

    /// A description dropped into the middle of a sentence mustn't bring its
    /// own full stop along — including the CJK ones a localized one ends in.
    private static func trimmedDescription(of error: Error) -> String {
        var text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".。．".contains(last) { text.removeLast() }
        return text
    }

    /// Mirrors `TimeInterval.formattedClock` ("1:02:33" / "12:05"). That one
    /// picks up the app's default MainActor isolation, so this `nonisolated`
    /// type can't call it.
    private static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// Why a saved conversation has no usable transcript. The audio is archived
/// either way; this shapes what the pane says about it and, for the two
/// failures, what its History row says about why it has no transcript.
///
/// Compiled with `TranscriptionFailure` into its harness, so a refusal reads
/// the same here as on the dictation card.
nonisolated enum MeetingTranscriptionIssue: Equatable {
    case noSpeech
    /// The transcription ran and failed. `reason` is whole sentences in the
    /// dictation card's words ("OpenAI says your account is out of credit.
    /// Top up, or transcribe with a model on this Mac.").
    case failed(reason: String)
    /// No engine could be loaded to try. `reason` names the model and why.
    case noModel(reason: String)

    /// A transcription that threw, explained the way the dictation card
    /// explains it. `provider` names the cloud service of the model that
    /// failed ("OpenAI"), nil for a model on this Mac.
    static func failed(_ error: Error, provider: String?) -> MeetingTranscriptionIssue {
        let fallback = sentence(engineReason(for: error))
        return .failed(reason: TranscriptionFailure.classify(error).message(provider: provider, fallback: fallback))
    }

    /// The model a conversation was meant for couldn't be loaded. Says which,
    /// and the most specific why there is: no model at all, a cloud model
    /// without its key (`missingKeyFor` names the provider), the error the
    /// last load left behind, or — a stalled download, say — only that it
    /// isn't ready.
    static func noModel(
        named modelName: String?,
        missingKeyFor provider: String?,
        loadFailure: String?
    ) -> MeetingTranscriptionIssue {
        guard let modelName else {
            return .noModel(reason: "No transcription model is selected.")
        }
        if let provider {
            return .noModel(reason: "\(modelName) needs an \(provider) API key.")
        }
        if let loadFailure, !loadFailure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .noModel(reason: "Couldn't load \(modelName): \(sentence(loadFailure))")
        }
        return .noModel(reason: "\(modelName) isn't ready. Check it in Models.")
    }

    /// Why the recording has no transcript, for its History row — which
    /// already says it isn't transcribed and offers to, so the reason is all
    /// it needs. Nil for no speech: that transcript is the model's answer.
    var historyReason: String? {
        switch self {
        case .noSpeech: return nil
        case .failed(let reason), .noModel(let reason): return reason
        }
    }

    /// Standalone text for a normal Stop or, naming `fileName`, an import.
    func message(fileName: String? = nil) -> String {
        switch self {
        case .noSpeech:
            return "No speech was detected, but the audio was saved to History."
        case .failed(let reason), .noModel(let reason):
            let subject = fileName.map { "“\($0)”" } ?? "the conversation"
            return "Couldn't transcribe \(subject): \(reason) The audio is saved in History, so you can transcribe it from there."
        }
    }

    /// Continues "…was saved to History, but " after an interruption, which has
    /// already said the audio was kept. Ends the sentence itself.
    var clause: String {
        switch self {
        case .noSpeech:
            return "no speech was detected."
        case .failed(let reason), .noModel(let reason):
            return "it couldn't be transcribed: \(reason) You can transcribe it from History."
        }
    }

    /// The engine's own account of what went wrong, without the "Transcription
    /// failed: " both engine error types lead with: the card already says so,
    /// and saying it twice was the old card's tell.
    static func engineReason(for error: Error) -> String {
        if let cloud = error as? CloudTranscriptionError { return cloud.reason }
        let description = error.localizedDescription
        let prefix = "Transcription failed: "
        return description.hasPrefix(prefix) ? String(description.dropFirst(prefix.count)) : description
    }

    /// `text` as a sentence another can follow: trimmed, with a full stop
    /// when it ends without one.
    static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "Something went wrong." }
        return ".!?。．！？".contains(last) ? trimmed : trimmed + "."
    }
}

/// Recorder failures surfaced to the controller. Lives here rather than beside
/// `MeetingRecorder` (which imports ScreenCaptureKit) so `reason(for:)` and its
/// harness can see the disk-write case.
nonisolated enum MeetingRecorderError: LocalizedError {
    case noDisplayAvailable
    /// The WAV writer's first failed write — usually a full disk.
    case diskWriteFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display is available to capture system audio from."
        case .diskWriteFailed(let underlying):
            return "The recording couldn't be written to disk: \(underlying.localizedDescription)"
        }
    }
}
