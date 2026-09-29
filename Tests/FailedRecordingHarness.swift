import Foundation

struct FailedRecordingHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw FailedRecordingHarnessFailure(description: message)
    }
}

private func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw FailedRecordingHarnessFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

private let failedID = UUID(uuidString: "5E1A2B3C-4D5E-4F60-8A1B-2C3D4E5F6071")!
private let placeholder = "⚠︎ Audio saved without a transcript."
private let refusedKey = RecordingHistoryEntry.Status(kind: .failed, message: "OpenAI didn't accept your API key.")

/// A dictation saved the way `recordFailed` saves one.
private func makeFailed(status: RecordingHistoryEntry.Status? = refusedKey) -> RecordingHistoryEntry {
    RecordingHistoryEntry(
        id: failedID,
        createdAt: Date(timeIntervalSince1970: 1_790_000_000),
        transcript: placeholder,
        audioFileName: "\(failedID.uuidString).wav",
        durationSeconds: 7.25,
        sampleRate: 16_000,
        modelId: "gpt-4o-transcribe",
        modelName: "GPT-4o Transcribe",
        source: .dictation,
        isFavorite: true,
        status: status
    )
}

/// A row exactly as builds before `status` wrote it.
private let legacyRow = """
[{
  "id": "0D9C8B7A-6F5E-4D3C-8B2A-190817161514",
  "createdAt": "2026-08-01T09:30:00Z",
  "transcript": "an ordinary dictation",
  "audioFileName": "0D9C8B7A-6F5E-4D3C-8B2A-190817161514.wav",
  "durationSeconds": 3.5,
  "sampleRate": 16000,
  "modelId": "parakeet",
  "modelName": "Parakeet",
  "source": "dictation"
}]
"""

@main
struct FailedRecordingHarness {
    static func main() throws {
        try indexesWithoutStatusStillDecode()
        try statusRoundTripsThroughTheIndex()
        try unknownStatusKindIsKeptNotDropped()
        try resolvingReplacesThePlaceholder()
        try resolvingNeedsAFailedEntry()
        try aRetryCanRestateTheFailure()
        try otherEditsKeepTheStatus()
        print("Failed recording harness passed")
    }

    private static func indexesWithoutStatusStillDecode() throws {
        let decoded = try HistoryIndexCodec.decode(Data(legacyRow.utf8))
        try expect(decoded.entries.count, 1, "the legacy row decodes")
        try expect(decoded.passthrough.isEmpty, true, "and isn't passed through")
        try expect(decoded.entries[0].status, nil, "absent status reads as a real transcript")
        try expect(decoded.entries[0].needsTranscript, false, "so it needs none")
    }

    private static func statusRoundTripsThroughTheIndex() throws {
        let noSpeech = makeFailed(status: .init(kind: .noSpeech, message: "No speech detected."))
        let data = try HistoryIndexCodec.encode(entries: [makeFailed(), noSpeech], passthrough: [])
        let decoded = try HistoryIndexCodec.decode(data)
        try expect(decoded.entries, [makeFailed(), noSpeech], "status survives a write and a read")
        try expect(decoded.entries[0].needsTranscript, true, "a failed take waits for a transcript")

        let plain = try HistoryIndexCodec.encode(entries: [makeFailed(status: nil)], passthrough: [])
        try expect(
            String(decoding: plain, as: UTF8.self).contains("\"status\""),
            false,
            "a transcribed entry writes no status key, so older builds read it unchanged"
        )
    }

    /// A newer build might add a kind; its row must survive this build rather
    /// than decode wrongly or vanish.
    private static func unknownStatusKindIsKeptNotDropped() throws {
        let data = try HistoryIndexCodec.encode(entries: [makeFailed()], passthrough: [])
        let future = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"failed\"", with: "\"queued\"")
        let decoded = try HistoryIndexCodec.decode(Data(future.utf8))
        try expect(decoded.entries.isEmpty, true, "this build can't read the unknown kind")
        try expect(decoded.passthrough.count, 1, "so the row is passed through")
        try expect(decoded.passthrough[0].audioFileName, "\(failedID.uuidString).wav", "and its audio stays referenced")
    }

    private static func resolvingReplacesThePlaceholder() throws {
        let failed = makeFailed()
        guard let resolved = failed.resolvingPlaceholder(
            transcript: "Send the draft to Kara by Friday.",
            modelId: "parakeet",
            modelName: "Parakeet"
        ) else {
            throw FailedRecordingHarnessFailure(description: "a failed entry resolves")
        }
        try expect(resolved.transcript, "Send the draft to Kara by Friday.", "the transcript replaces the placeholder")
        try expect(resolved.status, nil, "the status clears")
        try expect(resolved.needsTranscript, false, "nothing left to transcribe")
        try expect(resolved.alternates, nil, "the placeholder isn't kept as an alternate")
        try expect(resolved.hasAlternateTranscripts, false, "so the row shows one transcript")
        try expect(resolved.modelId, "parakeet", "the model that transcribed it is credited")
        try expect(resolved.id, failed.id, "same row")
        try expect(resolved.audioFileName, failed.audioFileName, "same audio")
        try expect(resolved.createdAt, failed.createdAt, "same date")
        try expect(resolved.durationSeconds, failed.durationSeconds, "same length")
        try expect(resolved.isFavorited, true, "a star made meanwhile stays")

        let unattributed = failed.resolvingPlaceholder(transcript: "hello", modelId: nil, modelName: nil)
        try expect(unattributed?.modelId, "gpt-4o-transcribe", "no model given keeps the one it was meant for")
    }

    private static func resolvingNeedsAFailedEntry() throws {
        try expect(
            makeFailed(status: nil).resolvingPlaceholder(transcript: "x", modelId: nil, modelName: nil),
            nil,
            "a real transcript is never replaced as if it were a placeholder"
        )
    }

    private static func aRetryCanRestateTheFailure() throws {
        let offline = RecordingHistoryEntry.Status(kind: .failed, message: "You're offline.")
        try expect(makeFailed().updatingStatus(offline)?.status, offline, "a retry that failed differently says so")
        try expect(makeFailed().updatingStatus(offline)?.transcript, placeholder, "and changes nothing else")
        try expect(makeFailed(status: nil).updatingStatus(offline), nil, "a transcribed entry can't be marked failed")
    }

    /// The `replacing` funnel's point: an edit that knows nothing about the
    /// status must not clear it, or a star click would hide the failure.
    private static func otherEditsKeepTheStatus() throws {
        let failed = makeFailed()
        try expect(failed.updatingFavorite(false).status, refusedKey, "unstarring")
        try expect(failed.updatingSpeakerNames(["Speaker 1": "Kara"]).status, refusedKey, "naming speakers")
        try expect(failed.updatingSummary(nil).status, refusedKey, "removing a summary")
        try expect(failed.updatingActionItems(nil).status, refusedKey, "removing action items")
        try expect(failed.updatingCustomInsights(nil).status, refusedKey, "removing custom results")
    }
}
