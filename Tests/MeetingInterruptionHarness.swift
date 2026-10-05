import Foundation

struct MeetingInterruptionHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw MeetingInterruptionHarnessFailure(description: message)
    }
}

private func streamError(_ code: Int) -> NSError {
    NSError(domain: MeetingInterruption.streamErrorDomain, code: code)
}

private struct DescribedError: LocalizedError {
    let errorDescription: String?
}

@main
struct MeetingInterruptionHarness {
    static func main() throws {
        try mapsStreamCodesToPlainReasons()
        try mapsDiskWriteFailures()
        try unknownErrorsFallBackToTheirDescription()
        try salvageNeedsAtLeastOneSecond()
        try composesSavedMessage()
        try composesSavedMessageWithTranscriptionIssue()
        try composesNothingCapturedMessage()
        try outOfSpaceAsksToFreeSpace()
        try composesUnfinishedMessage()
        try transcriptionIssueKeepsStandaloneMessages()
        try quotaRefusalSaysWhatToDo()
        try unclassifiedFailuresKeepTheEngineReason()
        try noModelNamesTheModelAndWhy()
        print("Meeting interruption harness passed")
    }

    private static func mapsStreamCodesToPlainReasons() throws {
        typealias Code = MeetingInterruption.StreamCode
        let reason = { MeetingInterruption.reason(for: streamError($0)) }
        try expect(reason(Code.userStopped) == "capture was stopped from the macOS screen-sharing indicator", "userStopped")
        try expect(reason(Code.systemStoppedStream) == "macOS stopped the audio capture", "systemStoppedStream")
        try expect(reason(Code.noCaptureSource) == "the display it was capturing from was disconnected", "noCaptureSource")
        try expect(reason(Code.noDisplayList) == "the display it was capturing from was disconnected", "noDisplayList")
        try expect(reason(Code.userDeclined) == "Screen Recording permission was turned off", "userDeclined")
        try expect(reason(Code.connectionInterrupted) == "macOS's screen capture service stopped unexpectedly", "connectionInterrupted")
        try expect(reason(Code.connectionInvalid) == "macOS's screen capture service stopped unexpectedly", "connectionInvalid")
        try expect(reason(Code.insufficientStorage) == "your Mac ran out of disk space", "insufficientStorage")
    }

    private static func mapsDiskWriteFailures() throws {
        // FileHandle wraps the POSIX errno in a generic Cocoa write error.
        let wrappedENOSPC = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteUnknownError,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))]
        )
        let outOfSpace = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let quota = NSError(domain: NSPOSIXErrorDomain, code: Int(EDQUOT))
        let otherIO = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteUnknownError,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))]
        )
        let reason = { MeetingInterruption.reason(for: MeetingRecorderError.diskWriteFailed($0)) }
        try expect(reason(wrappedENOSPC) == "your Mac ran out of disk space", "wrapped ENOSPC reads as a full disk")
        try expect(reason(outOfSpace) == "your Mac ran out of disk space", "Cocoa out-of-space reads as a full disk")
        try expect(reason(quota) == "your Mac ran out of disk space", "quota reads as a full disk")
        try expect(reason(otherIO) == "the recording couldn't be written to disk", "other write errors stay generic")
    }

    private static func unknownErrorsFallBackToTheirDescription() throws {
        let unknownCode = streamError(-3811)
        try expect(
            MeetingInterruption.reason(for: unknownCode) == unknownCode.localizedDescription
                .trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            "unmapped stream code falls back to its description"
        )
        let described = DescribedError(errorDescription: "The audio device went away.")
        try expect(
            MeetingInterruption.reason(for: described) == "The audio device went away",
            "fallback drops the trailing full stop so the sentence reads once"
        )
        let localized = DescribedError(errorDescription: "オーディオデバイスが見つかりません。")
        try expect(
            MeetingInterruption.reason(for: localized) == "オーディオデバイスが見つかりません",
            "fallback drops a CJK full stop too"
        )
        try expect(
            MeetingInterruption.reason(for: MeetingRecorderError.noDisplayAvailable)
                == "No display is available to capture system audio from",
            "non-disk recorder errors use their description"
        )
    }

    private static func salvageNeedsAtLeastOneSecond() throws {
        try expect(!MeetingInterruption.shouldSalvage(capturedSeconds: 0), "nothing captured is discarded")
        try expect(!MeetingInterruption.shouldSalvage(capturedSeconds: 0.99), "under a second is discarded")
        try expect(MeetingInterruption.shouldSalvage(capturedSeconds: 1.0), "a full second is kept")
        try expect(MeetingInterruption.shouldSalvage(capturedSeconds: 2_832), "a long conversation is kept")
    }

    private static func composesSavedMessage() throws {
        let message = MeetingInterruption.message(
            for: streamError(MeetingInterruption.StreamCode.systemStoppedStream),
            capturedSeconds: 2_832,
            transcriptionIssue: nil
        )
        try expect(
            message == "Recording stopped at 47:12 — macOS stopped the audio capture. Everything up to then was saved to History.",
            "clean salvage names when and why: \(message)"
        )
        let long = MeetingInterruption.message(
            for: DescribedError(errorDescription: "x"),
            capturedSeconds: 3_753.4,
            transcriptionIssue: nil
        )
        try expect(long.hasPrefix("Recording stopped at 1:02:33 — x."), "clock grows an hour field past an hour: \(long)")
    }

    private static func composesSavedMessageWithTranscriptionIssue() throws {
        let failed = MeetingInterruption.message(
            for: streamError(MeetingInterruption.StreamCode.userStopped),
            capturedSeconds: 65,
            transcriptionIssue: .failed(reason: "The request timed out.")
        )
        try expect(
            failed == "Recording stopped at 1:05 — capture was stopped from the macOS screen-sharing indicator. Everything up to then was saved to History, but it couldn't be transcribed: The request timed out. You can transcribe it from History.",
            "transcription failure is kept: \(failed)"
        )
        let other = DescribedError(errorDescription: "r")
        let silent = MeetingInterruption.message(for: other, capturedSeconds: 5, transcriptionIssue: .noSpeech)
        try expect(silent.hasSuffix("saved to History, but no speech was detected."), "no speech is kept: \(silent)")
        let noModel = MeetingInterruption.message(
            for: other,
            capturedSeconds: 5,
            transcriptionIssue: .noModel(named: "Parakeet", missingKeyFor: nil, loadFailure: nil)
        )
        try expect(
            noModel.hasSuffix("but it couldn't be transcribed: Parakeet isn't ready. Check it in Models. You can transcribe it from History."),
            "no model names the model: \(noModel)"
        )
    }

    private static func composesNothingCapturedMessage() throws {
        let message = MeetingInterruption.message(
            for: streamError(MeetingInterruption.StreamCode.userStopped),
            capturedSeconds: 0.4,
            transcriptionIssue: nil
        )
        try expect(
            message == "Recording stopped — capture was stopped from the macOS screen-sharing indicator. Nothing was captured.",
            "under a second says nothing was kept: \(message)"
        )
    }

    /// History's index write can fail on the same full disk, so the card mustn't
    /// promise the recording is safe without asking for space back.
    private static func outOfSpaceAsksToFreeSpace() throws {
        let diskFull = MeetingRecorderError.diskWriteFailed(
            NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        )
        let saved = MeetingInterruption.message(for: diskFull, capturedSeconds: 65, transcriptionIssue: .noSpeech)
        try expect(
            saved == "Recording stopped at 1:05 — your Mac ran out of disk space. Everything up to then was saved to History, but no speech was detected. Free up some disk space so VoiceToText can finish saving it.",
            "full disk asks for space after the outcome: \(saved)"
        )
        let streamFull = MeetingInterruption.message(
            for: streamError(MeetingInterruption.StreamCode.insufficientStorage),
            capturedSeconds: 65,
            transcriptionIssue: nil
        )
        try expect(streamFull.hasSuffix("so VoiceToText can finish saving it."), "SCStream's out-of-storage asks too: \(streamFull)")
        let otherIO = MeetingInterruption.message(
            for: MeetingRecorderError.diskWriteFailed(NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))),
            capturedSeconds: 65,
            transcriptionIssue: nil
        )
        try expect(otherIO.hasSuffix("saved to History."), "other write errors don't mention space: \(otherIO)")
        let nothing = MeetingInterruption.message(for: diskFull, capturedSeconds: 0.2, transcriptionIssue: nil)
        try expect(nothing.hasSuffix("Nothing was captured."), "nothing to keep, nothing to ask: \(nothing)")
    }

    private static func composesUnfinishedMessage() throws {
        let interrupted = MeetingInterruption.unfinishedMessage(
            interruption: streamError(MeetingInterruption.StreamCode.systemStoppedStream),
            capturedSeconds: 2_832
        )
        try expect(
            interrupted == "Recording stopped at 47:12 — macOS stopped the audio capture. The recording couldn't be finished writing to disk, so it was set aside. VoiceToText will try to recover it to History the next time it opens.",
            "unfinalized file after an interruption is set aside: \(interrupted)"
        )
        let stopped = MeetingInterruption.unfinishedMessage(interruption: nil, capturedSeconds: 2_400)
        try expect(
            stopped == "The 40:00 recording couldn't be finished writing to disk, so it was set aside. VoiceToText will try to recover it to History the next time it opens.",
            "unfinalized file after Stop never claims nothing was captured: \(stopped)"
        )
    }

    private static func transcriptionIssueKeepsStandaloneMessages() throws {
        try expect(
            MeetingTranscriptionIssue.noSpeech.message() == "No speech was detected, but the audio was saved to History.",
            "normal Stop wording unchanged for no speech"
        )
        try expect(
            MeetingTranscriptionIssue.noSpeech.message(fileName: "a.m4a") == "No speech was detected, but the audio was saved to History.",
            "an import with no speech reads the same"
        )
        try expect(MeetingTranscriptionIssue.noSpeech.historyReason == nil, "no speech isn't a failure on the row")
    }

    /// The incident behind this: a long conversation on an account with no
    /// credit left. The card used to read "Transcription failed (Transcription
    /// failed: OpenAI: You exceeded your current quota…). The audio was saved
    /// to History." — the prefix twice, and no word on what to do next.
    private static func quotaRefusalSaysWhatToDo() throws {
        let refusal = CloudTranscriptionError(
            cause: .http(status: 429, retryAfter: nil, apiCode: "insufficient_quota"),
            reason: "OpenAI: You exceeded your current quota, please check your plan and billing details."
        )
        let issue = MeetingTranscriptionIssue.failed(refusal, provider: "OpenAI")
        try expect(
            issue.historyReason == "OpenAI says your account is out of credit. Top up, or transcribe with a model on this Mac.",
            "the row carries the classified reason: \(issue.historyReason ?? "nil")"
        )
        let card = issue.message()
        try expect(
            card == "Couldn't transcribe the conversation: OpenAI says your account is out of credit. Top up, or transcribe with a model on this Mac. The audio is saved in History, so you can transcribe it from there.",
            "the card names the cause and the way back: \(card)"
        )
        try expect(!card.contains("Transcription failed"), "no doubled prefix: \(card)")
        let imported = issue.message(fileName: "interview.m4a")
        try expect(
            imported.hasPrefix("Couldn't transcribe “interview.m4a”: OpenAI says"),
            "an import names its file: \(imported)"
        )
    }

    /// What `TranscriptionFailure` can't classify keeps the engine's own words,
    /// without the "Transcription failed: " the card already implies.
    private static func unclassifiedFailuresKeepTheEngineReason() throws {
        let badFile = CloudTranscriptionError(
            cause: .http(status: 400, retryAfter: nil, apiCode: nil),
            reason: "OpenAI: Invalid file format"
        )
        try expect(
            MeetingTranscriptionIssue.failed(badFile, provider: "OpenAI").historyReason == "OpenAI: Invalid file format.",
            "a cloud error keeps its reason, made a sentence"
        )
        let engine = DescribedError(errorDescription: "Transcription failed: The model returned no segments")
        try expect(
            MeetingTranscriptionIssue.failed(engine, provider: nil).historyReason == "The model returned no segments.",
            "an engine error loses its prefix"
        )
        let local = DescribedError(errorDescription: "Couldn't read the audio file.")
        try expect(
            MeetingTranscriptionIssue.failed(local, provider: nil).historyReason == "Couldn't read the audio file.",
            "other errors are kept as they are"
        )
        try expect(MeetingTranscriptionIssue.sentence("  ") == "Something went wrong.", "an empty reason still says something")
        try expect(MeetingTranscriptionIssue.sentence("Done!") == "Done!", "existing punctuation is kept")
    }

    private static func noModelNamesTheModelAndWhy() throws {
        try expect(
            MeetingTranscriptionIssue.noModel(named: nil, missingKeyFor: nil, loadFailure: nil).historyReason
                == "No transcription model is selected.",
            "no model at all"
        )
        try expect(
            MeetingTranscriptionIssue.noModel(named: "GPT-4o Transcribe", missingKeyFor: "OpenAI", loadFailure: "x").historyReason
                == "GPT-4o Transcribe needs an OpenAI API key.",
            "a missing key outranks the load error it caused"
        )
        try expect(
            MeetingTranscriptionIssue.noModel(named: "Parakeet", missingKeyFor: nil, loadFailure: "The download was interrupted").historyReason
                == "Couldn't load Parakeet: The download was interrupted.",
            "a load failure is passed on"
        )
        try expect(
            MeetingTranscriptionIssue.noModel(named: "Parakeet", missingKeyFor: nil, loadFailure: " ").historyReason
                == "Parakeet isn't ready. Check it in Models.",
            "a blank load failure falls back to not ready"
        )
        let card = MeetingTranscriptionIssue.noModel(named: "Parakeet", missingKeyFor: nil, loadFailure: nil).message()
        try expect(
            card == "Couldn't transcribe the conversation: Parakeet isn't ready. Check it in Models. The audio is saved in History, so you can transcribe it from there.",
            "no model card: \(card)"
        )
    }
}
