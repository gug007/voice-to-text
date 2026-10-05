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
private func makeFailed(
    status: RecordingHistoryEntry.Status? = refusedKey,
    transcript: String = placeholder
) -> RecordingHistoryEntry {
    RecordingHistoryEntry(
        id: failedID,
        createdAt: Date(timeIntervalSince1970: 1_790_000_000),
        transcript: transcript,
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
        try placeholdersLiveOnTheEntry()
        try legacyPlaceholderRowsResolveInPlace()
        try legacyLookalikesAreLeftAlone()
        print("Failed recording harness passed")
    }

    /// The store, the conversation controller and this harness all write the
    /// same words; the entry is where they are defined and recognized.
    private static func placeholdersLiveOnTheEntry() throws {
        try expect(RecordingHistoryEntry.placeholderTranscript, placeholder, "the placeholder every build has written")
        try expect(
            RecordingHistoryEntry.knownPlaceholderTranscripts.contains(RecordingHistoryEntry.legacyRecoveredTranscript),
            true,
            "launch recovery's old wording is known too"
        )
        try expect(makeFailed().transcriptIsPlaceholder, true, "a failed take's transcript is a placeholder")
        try expect(makeFailed(status: nil).transcriptIsPlaceholder, true, "and so is the same text without a status")
    }

    /// A conversation archived by a build before `status`: the placeholder
    /// and nothing to say it is one. Transcribing it again must replace it —
    /// not file it as a "version" beside the real transcript.
    private static func legacyPlaceholderRowsResolveInPlace() throws {
        for legacyText in RecordingHistoryEntry.knownPlaceholderTranscripts {
            let legacy = legacyConversation(transcript: legacyText)
            try expect(legacy.needsTranscript, false, "no status, so the row doesn't claim a failure it can't explain")
            try expect(legacy.transcriptIsPlaceholder, true, "but its text is recognized as no transcript")
            guard let resolved = legacy.resolvingPlaceholder(
                transcript: "Kara: Let's ship on Friday.",
                modelId: "parakeet",
                modelName: "Parakeet"
            ) else {
                throw FailedRecordingHarnessFailure(description: "a legacy placeholder row resolves: \(legacyText)")
            }
            try expect(resolved.transcript, "Kara: Let's ship on Friday.", "the transcript replaces the placeholder")
            try expect(resolved.alternates, nil, "the placeholder isn't kept as an alternate")
            try expect(resolved.status, nil, "still no status")
            try expect(resolved.modelName, "Parakeet", "the model that transcribed it is credited")
            try expect(resolved.transcriptIsPlaceholder, false, "and it's a real transcript now")
            try expect(resolved.resolvingPlaceholder(transcript: "x", modelId: nil, modelName: nil), nil, "which is never replaced again")
        }
    }

    /// Only an exact placeholder with nothing else behind it qualifies.
    private static func legacyLookalikesAreLeftAlone() throws {
        let mentioned = legacyConversation(transcript: "I said ⚠︎ Audio saved without a transcript. on the call")
        try expect(mentioned.transcriptIsPlaceholder, false, "a transcript that merely contains the words is real")
        try expect(mentioned.resolvingPlaceholder(transcript: "x", modelId: nil, modelName: nil), nil, "and isn't replaced")

        let regenerated = legacyConversation(
            transcript: placeholder,
            alternates: [TranscriptVariant(id: UUID(), text: "the real one", modelId: "parakeet", modelName: "Parakeet")]
        )
        try expect(regenerated.transcriptIsPlaceholder, false, "a row with versions has had a transcript; its active one was chosen")
        try expect(regenerated.resolvingPlaceholder(transcript: "x", modelId: nil, modelName: nil), nil, "so it isn't replaced")

        let padded = legacyConversation(transcript: "  \(placeholder)\n")
        try expect(padded.transcriptIsPlaceholder, true, "surrounding whitespace doesn't hide a placeholder")
    }

    private static func legacyConversation(
        transcript: String,
        alternates: [TranscriptVariant]? = nil
    ) -> RecordingHistoryEntry {
        let id = UUID(uuidString: "7B1C2D3E-4F50-4A61-9B72-8C9DAEBFC0D1")!
        return RecordingHistoryEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            transcript: transcript,
            audioFileName: "\(id.uuidString).wav",
            durationSeconds: 2_400,
            sampleRate: 16_000,
            modelId: nil,
            modelName: nil,
            source: .meeting,
            alternates: alternates
        )
    }

    private static func indexesWithoutStatusStillDecode() throws {
        let decoded = try HistoryIndexCodec.decode(Data(legacyRow.utf8))
        try expect(decoded.entries.count, 1, "the legacy row decodes")
        try expect(decoded.passthrough.isEmpty, true, "and isn't passed through")
        try expect(decoded.entries[0].status, nil, "absent status reads as a real transcript")
        try expect(decoded.entries[0].needsTranscript, false, "so it needs none")
    }

    private static func statusRoundTripsThroughTheIndex() throws {
        let offline = makeFailed(status: .init(kind: .failed, message: "You're offline."))
        let data = try HistoryIndexCodec.encode(entries: [makeFailed(), offline], passthrough: [])
        let decoded = try HistoryIndexCodec.decode(data)
        try expect(decoded.entries, [makeFailed(), offline], "status survives a write and a read")
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
            makeFailed(status: nil, transcript: "Send the draft to Kara.")
                .resolvingPlaceholder(transcript: "x", modelId: nil, modelName: nil),
            nil,
            "a real transcript is never replaced as if it were a placeholder"
        )
    }

    private static func aRetryCanRestateTheFailure() throws {
        let offline = RecordingHistoryEntry.Status(kind: .failed, message: "You're offline.")
        try expect(makeFailed().updatingStatus(offline)?.status, offline, "a retry that failed differently says so")
        try expect(makeFailed().updatingStatus(offline)?.transcript, placeholder, "and changes nothing else")
        try expect(
            makeFailed(status: nil, transcript: "Send the draft to Kara.").updatingStatus(offline),
            nil,
            "a transcribed entry can't be marked failed"
        )
        let legacy = makeFailed(status: nil, transcript: RecordingHistoryEntry.legacyRecoveredTranscript)
        try expect(legacy.updatingStatus(offline)?.status, offline, "an older build's placeholder row takes the reason it never had")
        try expect(
            legacy.updatingStatus(offline)?.transcript,
            RecordingHistoryEntry.legacyRecoveredTranscript,
            "and keeps its placeholder until a transcript replaces it"
        )
        try expect(
            makeFailed(status: nil).updatingStatus(offline)?.status,
            offline,
            "so does one carrying today's placeholder with no status"
        )
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
