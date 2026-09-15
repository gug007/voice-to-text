import Foundation

struct HarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String
) throws {
    if actual != expected {
        throw HarnessFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

/// A recording with every optional field populated, so any copy helper that
/// drops one shows up as an inequality rather than as a field nobody checked.
private func makeFullEntry(
    id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
    transcript: String = "Speaker 1: we ship on Friday."
) -> RecordingHistoryEntry {
    let generatedAt = Date(timeIntervalSince1970: 1_756_000_000)
    return RecordingHistoryEntry(
        id: id,
        createdAt: Date(timeIntervalSince1970: 1_755_000_000),
        transcript: transcript,
        audioFileName: "\(id.uuidString).wav",
        durationSeconds: 92.5,
        sampleRate: 16_000,
        modelId: "parakeet",
        modelName: "Parakeet",
        source: .meeting,
        isFavorite: true,
        alternates: [
            TranscriptVariant(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                text: "older take",
                modelId: "whisper",
                modelName: "Whisper"
            )
        ],
        speakerNames: ["Speaker 1": "Kara"],
        summary: TranscriptSummary(
            text: "The team agreed to ship on Friday.",
            generatedAt: generatedAt,
            modelId: "gpt-5.5",
            sourceDigest: TranscriptDigest.of(transcript)
        ),
        actionItems: TranscriptActionItems(
            items: [
                ActionItem(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    text: "Send the release notes",
                    owner: "Dan",
                    due: "before Friday"
                ),
                ActionItem(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    text: "Book the room",
                    isDone: true
                ),
            ],
            generatedAt: generatedAt,
            modelId: "gpt-5.5",
            sourceDigest: TranscriptDigest.of(transcript)
        )
    )
}

private func historyEncoder() -> JSONEncoder {
    // Mirrors RecordingHistoryStore.persistIndex.
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

private func historyDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

@main
struct TranscriptInsightHarness {
    static func main() throws {
        try testLegacyIndexDecodesWithoutInsights()
        try testInsightRoundTrip()
        try testCopyHelpersPreserveEveryField()
        try testDigestIsStableAndContentSensitive()
        try testStaleness()
        try testActionItemToggling()
        try testSummaryRequestBody()
        try testActionItemsRequestBody()
        try testFragmentPrompt()
        try testSummaryReduceBody()
        try testParseActionItems()
        try testOwnerRulesRejectLabelsAndDeadlines()
        try testParaphrasedSchemaFallsThrough()
        try testMergingDeduplicates()
        try testDoneFlagsSurviveRegeneration()
        try testOwnerExamplesAvoidSpeakerLabels()
        try testChunker()
        try testSummaryLayout()
        print("TranscriptInsightHarness: all checks passed")
    }

    // MARK: - Persistence

    /// The compatibility case that matters: every index.json already on a user's
    /// disk was written before insights existed and has neither key.
    private static func testLegacyIndexDecodesWithoutInsights() throws {
        let legacy = Data("""
        [{
          "id": "9E1C1E2E-0000-4000-8000-000000000001",
          "createdAt": "2026-08-02T09:10:00Z",
          "transcript": "hello world",
          "audioFileName": "9E1C1E2E-0000-4000-8000-000000000001.wav",
          "durationSeconds": 3.5,
          "sampleRate": 16000,
          "modelId": "parakeet",
          "modelName": "Parakeet",
          "source": "meeting",
          "isFavorite": true
        }]
        """.utf8)
        let decoded = try historyDecoder().decode([RecordingHistoryEntry].self, from: legacy)
        try expect(decoded.count, 1, "an index without the insight keys still decodes")
        try expect(decoded[0].summary == nil, true, "an absent summary key decodes as nil")
        try expect(decoded[0].actionItems == nil, true, "an absent actionItems key decodes as nil")
        try expect(decoded[0].hasInsights, false, "a legacy entry shows no tab bar")
        try expect(decoded[0].hasInsight(.summary), false, "hasInsight is false for a missing summary")
        try expect(decoded[0].isStale(.summary), false, "a missing insight is never stale")
        try expect(decoded[0].transcript, "hello world", "the rest of the entry is unaffected")
        try expect(decoded[0].isFavorited, true, "the rest of the entry is unaffected")
    }

    private static func testInsightRoundTrip() throws {
        let entry = makeFullEntry()
        let data = try historyEncoder().encode([entry])
        let decoded = try historyDecoder().decode([RecordingHistoryEntry].self, from: data)
        try expect(decoded, [entry], "a fully populated entry round-trips through index.json")
        try expect(decoded[0].summary?.text, "The team agreed to ship on Friday.", "summary text persists")
        try expect(decoded[0].actionItems?.items.count, 2, "every action item persists")
        try expect(decoded[0].actionItems?.items[0].owner, "Dan", "owners persist")
        try expect(decoded[0].actionItems?.items[0].due, "before Friday", "due text persists")
        try expect(decoded[0].actionItems?.doneCount, 1, "checked state persists")
    }

    // MARK: - Copy helpers

    /// Each helper is asked to change one thing and then change it back; if it
    /// drops any other field on the way, the restored entry stops being equal to
    /// the original. This is the regression that motivated the whole exercise —
    /// a star click used to rebuild the entry by hand.
    private static func testCopyHelpersPreserveEveryField() throws {
        let entry = makeFullEntry()

        let regenerated = entry.updatingTranscripts(
            transcript: "a fresh take",
            modelId: "whisper",
            modelName: "Whisper",
            alternates: nil
        )
        try expect(regenerated.transcript, "a fresh take", "updatingTranscripts replaces the transcript")
        try expect(regenerated.summary, entry.summary, "regeneration keeps the summary (it goes stale, not away)")
        try expect(regenerated.actionItems, entry.actionItems, "regeneration keeps the action items")
        try expect(regenerated.isFavorited, true, "regeneration keeps the star")
        try expect(regenerated.speakerNames, entry.speakerNames, "regeneration keeps speaker names")
        let restored = regenerated.updatingTranscripts(
            transcript: entry.transcript,
            modelId: entry.modelId,
            modelName: entry.modelName,
            alternates: entry.alternates
        )
        try expect(restored, entry, "updatingTranscripts changes nothing but what it is given")

        let renamed = entry.updatingSpeakerNames(["Speaker 1": "Dan"])
        try expect(renamed.speakerNames, ["Speaker 1": "Dan"], "updatingSpeakerNames replaces the map")
        try expect(renamed.summary, entry.summary, "renaming a speaker keeps the summary")
        try expect(renamed.actionItems, entry.actionItems, "renaming a speaker keeps the action items")
        try expect(
            renamed.updatingSpeakerNames(entry.speakerNames), entry,
            "updatingSpeakerNames changes nothing but the names"
        )

        let unstarred = entry.updatingFavorite(false)
        try expect(unstarred.isFavorited, false, "updatingFavorite replaces the star")
        try expect(unstarred.summary, entry.summary, "unstarring keeps the summary")
        try expect(unstarred.actionItems, entry.actionItems, "unstarring keeps the action items")
        try expect(unstarred.updatingFavorite(true), entry, "updatingFavorite changes nothing but the star")

        let cleared = entry.updatingSummary(nil).updatingActionItems(nil)
        try expect(cleared.hasInsights, false, "both insights can be removed")
        try expect(cleared.transcript, entry.transcript, "removing insights keeps the transcript")
        try expect(cleared.isFavorited, true, "removing insights keeps the star")
        try expect(
            cleared.updatingSummary(entry.summary).updatingActionItems(entry.actionItems), entry,
            "the insight setters change nothing else"
        )
    }

    // MARK: - Digest and staleness

    private static func testDigestIsStableAndContentSensitive() throws {
        try expect(TranscriptDigest.of("hello"), TranscriptDigest.of("hello"), "same input, same digest")
        try expect(
            TranscriptDigest.of("hello") != TranscriptDigest.of("hello."),
            true,
            "a one-character change changes the digest"
        )
        // Hard-coded FNV-1a 64 values. The point of the whole type is that these
        // hold in the *next* process too — Swift's String.hashValue is seeded per
        // process, so storing one would make every insight read as stale after a
        // relaunch. If these constants ever need updating, the stored digests of
        // every user's insights have been invalidated.
        try expect(TranscriptDigest.of("hello"), "a430d84680aabd0b", "FNV-1a 64 of \"hello\"")
        try expect(
            TranscriptDigest.of("Kara: we ship on Friday."),
            "eb75d581f417bb7a",
            "FNV-1a 64 of a transcript line"
        )
        try expect(TranscriptDigest.of(""), "cbf29ce484222325", "empty input is the FNV offset basis")
        try expect(TranscriptDigest.of("hello").count, 16, "always 16 lowercase hex characters")
        try expect(
            TranscriptDigest.of("hello") != String("hello".hashValue, radix: 16),
            true,
            "the digest is not the process-seeded hashValue"
        )
    }

    private static func testStaleness() throws {
        let entry = makeFullEntry()
        try expect(entry.isStale(.summary), false, "an insight is fresh right after generation")
        try expect(entry.isStale(.actionItems), false, "an insight is fresh right after generation")

        let regenerated = entry.updatingTranscripts(
            transcript: "a different transcript",
            modelId: entry.modelId,
            modelName: entry.modelName,
            alternates: entry.alternates
        )
        try expect(regenerated.isStale(.summary), true, "changing the transcript makes the summary stale")
        try expect(regenerated.isStale(.actionItems), true, "changing the transcript makes the items stale")
        try expect(regenerated.hasInsights, true, "stale is not gone")

        // A speaker rename is a display-time relabel of the same stored text, so
        // it must not make anything stale.
        try expect(
            entry.updatingSpeakerNames(["Speaker 1": "Dan"]).isStale(.summary),
            false,
            "renaming a speaker leaves the insight fresh"
        )
    }

    // MARK: - Checklist

    private static func testActionItemToggling() throws {
        let items = makeFullEntry().actionItems!
        try expect(items.doneCount, 1, "doneCount counts the checked items")

        let first = items.items[0].id
        let toggled = items.toggling(itemID: first)
        try expect(toggled.items[0].isDone, true, "the targeted item flips")
        try expect(toggled.items[1].isDone, true, "the other item is untouched")
        try expect(toggled.items[1], items.items[1], "the other item is byte-for-byte the same")
        try expect(toggled.items[0].text, items.items[0].text, "toggling changes nothing but the checkbox")
        try expect(toggled.items[0].owner, "Dan", "toggling keeps the owner")
        try expect(toggled.doneCount, 2, "doneCount tracks the toggle")
        try expect(toggled.generatedAt, items.generatedAt, "toggling keeps the generation stamp")
        try expect(toggled.sourceDigest, items.sourceDigest, "toggling does not make the list stale")

        try expect(toggled.toggling(itemID: first), items, "toggling twice returns to the start")
        try expect(items.toggling(itemID: UUID()), items, "an unknown id is a no-op")
    }

    // MARK: - Request bodies

    private static func testSummaryRequestBody() throws {
        let data = try TranscriptInsightRequest.makeRequestBody(
            kind: .summary,
            text: "Kara: we ship on Friday.",
            modelId: "gpt-5.5"
        )
        let payload = try object(data)
        try expect(payload["model"] as? String, "gpt-5.5", "the body carries the model id")
        try expect(
            payload["temperature"] == nil, true,
            "no temperature override — GPT-5-family models reject non-default values"
        )
        try expect(
            payload["response_format"] == nil, true,
            "a summary is plain text, so it asks for no structured output"
        )
        let messages = payload["messages"] as? [[String: Any]] ?? []
        try expect(messages.count, 2, "system + user")
        try expect(messages[0]["role"] as? String, "system", "the prompt goes in the system message")
        try expect(
            (messages[0]["content"] as? String)?.contains("You write the summary of a recorded conversation") ?? false,
            true,
            "the system message is the product's summary prompt"
        )
        try expect(messages[1]["role"] as? String, "user", "the transcript goes in the user message")
        try expect(
            messages[1]["content"] as? String, "Kara: we ship on Friday.",
            "the transcript passes through unmodified"
        )
    }

    /// OpenAI rejects a `strict: true` schema outright unless every object lists
    /// all its properties in `required` and sets `additionalProperties: false`,
    /// so the shape is asserted here rather than discovered as a 400 in the field.
    private static func testActionItemsRequestBody() throws {
        let data = try TranscriptInsightRequest.makeRequestBody(
            kind: .actionItems,
            text: "Dan: I'll send the deck.",
            modelId: "gpt-5.5"
        )
        let payload = try object(data)
        try expect(payload["temperature"] == nil, true, "still no temperature key")

        let format = payload["response_format"] as? [String: Any] ?? [:]
        try expect(format["type"] as? String, "json_schema", "action items use structured output")
        let envelope = format["json_schema"] as? [String: Any] ?? [:]
        try expect(envelope["name"] as? String, "action_items", "the schema is named")
        try expect(envelope["strict"] as? Bool, true, "strict mode is on")

        let schema = envelope["schema"] as? [String: Any] ?? [:]
        try expect(schema["type"] as? String, "object", "the root is an object")
        try expect(schema["additionalProperties"] as? Bool, false, "the root forbids extra properties")
        try expect(schema["required"] as? [String], ["items"], "the root requires items")

        let properties = schema["properties"] as? [String: Any] ?? [:]
        let itemsSchema = properties["items"] as? [String: Any] ?? [:]
        try expect(itemsSchema["type"] as? String, "array", "items is an array")

        let item = itemsSchema["items"] as? [String: Any] ?? [:]
        try expect(item["type"] as? String, "object", "each item is an object")
        try expect(item["additionalProperties"] as? Bool, false, "each item forbids extra properties")
        let itemProperties = item["properties"] as? [String: Any] ?? [:]
        try expect(
            Set(itemProperties.keys), ["task", "owner", "due"],
            "each item carries exactly task, owner and due"
        )
        try expect(
            Set(item["required"] as? [String] ?? []), Set(itemProperties.keys),
            "strict mode requires every property to be listed in required"
        )
        try expect(
            (itemProperties["task"] as? [String: Any])?["type"] as? String, "string",
            "the task is always a string"
        )
        for nullable in ["owner", "due"] {
            try expect(
                (itemProperties[nullable] as? [String: Any])?["type"] as? [String], ["string", "null"],
                "\(nullable) is nullable rather than absent — strict mode has no optional keys"
            )
        }
    }

    private static func testFragmentPrompt() throws {
        let whole = TranscriptInsightRequest.systemPrompt(for: .summary)
        try expect(whole, TranscriptInsightRequest.summaryPrompt, "an unchunked job gets the prompt verbatim")

        let fragment = TranscriptInsightRequest.systemPrompt(for: .summary, part: (index: 2, total: 5))
        try expect(fragment.contains("part 2 of 5"), true, "a chunked job says which part it is looking at")
        try expect(fragment.contains("fragment"), true, "and that it is a fragment, not the whole conversation")
        try expect(
            fragment.hasSuffix(TranscriptInsightRequest.summaryPrompt), true,
            "the fragment note is prepended; the product prompt is unchanged"
        )

        let items = TranscriptInsightRequest.systemPrompt(for: .actionItems, part: (index: 1, total: 3))
        try expect(items.contains("part 1 of 3"), true, "action items get the same treatment")
        try expect(items.hasSuffix(TranscriptInsightRequest.actionItemsPrompt), true, "…on top of their own prompt")
    }

    private static func testSummaryReduceBody() throws {
        let data = try TranscriptInsightRequest.makeSummaryReduceBody(
            partialSummaries: ["First half.", "Second half."],
            modelId: "gpt-5.5"
        )
        let payload = try object(data)
        try expect(payload["model"] as? String, "gpt-5.5", "the reduce carries the model id")
        try expect(payload["temperature"] == nil, true, "still no temperature key")
        let messages = payload["messages"] as? [[String: Any]] ?? []
        try expect(messages.count, 2, "system + user")
        try expect(
            (messages[0]["content"] as? String)?.contains("consecutive parts of ONE conversation") ?? false,
            true,
            "the reduce prompt says the parts are one conversation"
        )
        let user = messages[1]["content"] as? String ?? ""
        try expect(user.contains("Part 1 of 2"), true, "each partial is labelled with its position")
        try expect(user.contains("First half."), true, "the first partial is included")
        try expect(user.contains("Second half."), true, "the second partial is included")
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HarnessFailure(description: "request body is not a JSON object")
        }
        return payload
    }

    // MARK: - Parsing

    private static func testParseActionItems() throws {
        let clean = """
        {"items":[{"task":"Send the deck","owner":"Dan","due":"before Friday"},
                  {"task":"Book the room","owner":null,"due":null}]}
        """
        guard let parsed = TranscriptInsightRequest.parseActionItems(from: clean) else {
            throw HarnessFailure(description: "clean JSON did not parse")
        }
        try expect(parsed.count, 2, "both items are read")
        try expect(parsed[0].text, "Send the deck", "the task text is read")
        try expect(parsed[0].owner, "Dan", "the owner is read")
        try expect(parsed[0].due, "before Friday", "the due text is read")
        try expect(parsed[1].owner, nil, "a JSON null owner stays nil")
        try expect(parsed[1].due, nil, "a JSON null due stays nil")

        let fenced = "```json\n{\"items\":[{\"task\":\"Send the deck\",\"owner\":null,\"due\":null}]}\n```"
        try expect(
            TranscriptInsightRequest.parseActionItems(from: fenced)?.first?.text, "Send the deck",
            "JSON wrapped in a markdown fence still parses"
        )

        let withProse = """
        Sure — here are the action items I found:

        {"items":[{"task":"Review the budget","owner":"Kara","due":null}]}
        """
        try expect(
            TranscriptInsightRequest.parseActionItems(from: withProse)?.first?.owner, "Kara",
            "JSON behind a sentence of preamble still parses"
        )

        let empty = TranscriptInsightRequest.parseActionItems(from: #"{"items":[]}"#)
        try expect(empty?.isEmpty, true, "an explicitly empty list is a success, not a failure")

        // "null" as a *string*, which models produce when they paraphrase the
        // schema rather than following it.
        try expect(
            TranscriptInsightRequest.parseActionItems(from: #"{"items":[{"task":"Ship","owner":"none","due":"N/A"}]}"#)?.first?.owner,
            nil,
            "a placeholder owner is treated as no owner"
        )

        let bulleted = """
        Here is what came up:
        - Dan: send the release notes
        * Review the budget (Kara)
        1. Book the room
        """
        guard let lines = TranscriptInsightRequest.parseActionItems(from: bulleted) else {
            throw HarnessFailure(description: "bulleted fallback did not parse")
        }
        try expect(lines.count, 3, "every bullet style is read")
        try expect(lines[0].text, "send the release notes", "a leading name is pulled out of the text")
        try expect(lines[0].owner, "Dan", "…and becomes the owner")
        try expect(lines[1].text, "Review the budget", "a trailing parenthetical is pulled out of the text")
        try expect(lines[1].owner, "Kara", "…and becomes the owner")
        try expect(lines[2].text, "Book the room", "a numbered bullet is read")
        try expect(lines[2].owner, nil, "an unattributed item has no owner")

        try expect(
            TranscriptInsightRequest.parseActionItems(from: "The conversation produced nothing usable."),
            nil,
            "an unparseable reply returns nil so the row can report a failure"
        )
        try expect(TranscriptInsightRequest.parseActionItems(from: ""), nil, "an empty reply returns nil")
    }

    /// Every one of these used to render a person-icon chip naming somebody who
    /// was never in the meeting: a section heading, a status, or — worst — a
    /// deadline, which also left the clock chip empty.
    private static func testOwnerRulesRejectLabelsAndDeadlines() throws {
        let reply = """
        - Decision: ship on Friday
        - Note: nobody owns this yet
        - Open questions: whether we ship on Friday
        - Send the deck (by Friday)
        - Ship the release (blocked on QA)
        - Send the report (Q3, revised)
        """
        guard let parsed = TranscriptInsightRequest.parseActionItems(from: reply) else {
            throw HarnessFailure(description: "the bulleted fallback did not parse")
        }
        try expect(parsed.count, 6, "every line is still read as an item")
        try expect(parsed.allSatisfy { $0.owner == nil }, true, "none of these is a person")
        try expect(parsed[0].text, "Decision: ship on Friday", "a rejected label keeps the line whole")
        try expect(parsed[3].text, "Send the deck (by Friday)", "a rejected deadline keeps the line whole")
        try expect(parsed[5].text, "Send the report (Q3, revised)", "anything with a digit keeps the line whole")

        // The rule still has to let real names through, or the fallback stops
        // extracting owners at all.
        let named = TranscriptInsightRequest.parseActionItems(from: """
        - Dan: send the release notes
        - Review the budget (Kara)
        - Ship the beta (the ticketing team)
        """)
        try expect(named?.map(\.owner), ["Dan", "Kara", "the ticketing team"], "real names still become owners")
    }

    /// `Wire` has every property optional, so a paraphrased schema decodes fine
    /// and yields nothing. Reporting that as an empty success tells the user the
    /// meeting committed nobody to anything while the model had in fact listed
    /// the work — and stores that emptiness so it is never re-tried.
    private static func testParaphrasedSchemaFallsThrough() throws {
        try expect(
            TranscriptInsightRequest.parseActionItems(
                from: #"{"items":[{"description":"Send the deck","assignee":"Dan"}]}"#
            ),
            nil,
            "a list whose keys are all unrecognised is not an empty success"
        )
        try expect(
            TranscriptInsightRequest.parseActionItems(
                from: #"{"action_items":[{"item":"Send the release notes","responsible":"Dan"}]}"#
            ),
            nil,
            "…the same under the action_items envelope"
        )
        try expect(
            TranscriptInsightRequest.parseActionItems(from: #"{"items":[{}]}"#), nil,
            "…and for an item with no keys at all"
        )
        try expect(
            TranscriptInsightRequest.parseActionItems(from: "Nothing to do here. []"), nil,
            "a stray empty bracket in prose is not an empty success"
        )
        // The bracket span must not swallow a list the line reader can read.
        let strayBracket = """
        Here is what came up:
        - Dan: send the release notes
        []
        """
        try expect(
            TranscriptInsightRequest.parseActionItems(from: strayBracket)?.count, 1,
            "a stray bracket does not hide the bulleted list above it"
        )
    }

    private static func testMergingDeduplicates() throws {
        let merged = TranscriptInsightRequest.merging([
            .init(text: "Send the deck", owner: "Dan", due: "Friday"),
            .init(text: "send the deck.", owner: nil, due: nil),
            .init(text: "Book the room", owner: nil, due: nil),
        ])
        try expect(merged.count, 2, "a restated item from the next chunk is dropped")
        try expect(merged[0].owner, "Dan", "the first occurrence wins, keeping its owner")
        try expect(merged[1].text, "Book the room", "distinct items survive in order")

        // Three people committing to the same chore in a standup is three
        // commitments, not one — and collapsing them only ever happened on the
        // long, chunked recordings where the checklist matters most.
        let sameTask = TranscriptInsightRequest.merging([
            .init(text: "Update the tracker", owner: "Dan", due: nil),
            .init(text: "Update the tracker", owner: "Kara", due: "Monday"),
            .init(text: "update the tracker.", owner: "Sam", due: nil),
        ])
        try expect(sameTask.map(\.owner), ["Dan", "Kara", "Sam"], "a shared task keeps every owner")
        try expect(sameTask[1].due, "Monday", "…and every owner's own deadline")

        let backfilled = TranscriptInsightRequest.merging([
            .init(text: "Book the room", owner: nil, due: nil),
            .init(text: "book the room.", owner: "Kara", due: "Friday"),
        ])
        try expect(backfilled.count, 1, "a later mention of an unattributed task folds into it")
        try expect(backfilled[0].owner, "Kara", "…and back-fills the owner it was missing")
        try expect(backfilled[0].due, "Friday", "…and the deadline it was missing")
        try expect(backfilled[0].text, "Book the room", "the first wording is kept")

        let symbolOnly = TranscriptInsightRequest.merging([.init(text: "→", owner: nil, due: nil)])
        try expect(symbolOnly.count, 1, "a task that folds to an empty key is kept, not deleted")
    }

    /// The done flags are the only user-entered data the insights layer holds and
    /// exist nowhere else, so a regeneration — which the stale banner actively
    /// recommends — must not wipe them.
    private static func testDoneFlagsSurviveRegeneration() throws {
        let previous = makeFullEntry().actionItems!
        try expect(previous.items[1].isDone, true, "the fixture has one checked item")

        let fresh = TranscriptActionItems(
            items: [
                ActionItem(text: "Book the room."),
                ActionItem(text: "Send the release notes"),
                ActionItem(text: "Draft the changelog"),
            ],
            generatedAt: Date(timeIntervalSince1970: 1_757_000_000),
            modelId: "gpt-5.5",
            sourceDigest: "0123456789abcdef"
        )
        let carried = TranscriptInsightRequest.carryingDoneFlags(from: previous, onto: fresh)
        try expect(carried.items[0].isDone, true, "a re-worded restatement of a checked task stays checked")
        try expect(carried.items[1].isDone, false, "an item that was never checked stays unchecked")
        try expect(carried.items[2].isDone, false, "a brand new item starts unchecked")
        try expect(carried.items.map(\.id), fresh.items.map(\.id), "the new list keeps its own ids")
        try expect(carried.generatedAt, fresh.generatedAt, "the new generation stamp is kept")
        try expect(carried.sourceDigest, fresh.sourceDigest, "the new list is not marked stale")

        try expect(
            TranscriptInsightRequest.carryingDoneFlags(from: nil, onto: fresh), fresh,
            "a first generation has nothing to carry"
        )
        let noneChecked = previous.toggling(itemID: previous.items[1].id)
        try expect(
            TranscriptInsightRequest.carryingDoneFlags(from: noneChecked, onto: fresh), fresh,
            "a previous list with nothing checked passes the new one through untouched"
        )
    }

    /// The model reads the transcript with the user's speaker names already
    /// applied, so holding up a canonical label as a good owner value would ask
    /// it to write names that are nowhere on screen.
    private static func testOwnerExamplesAvoidSpeakerLabels() throws {
        try expect(
            TranscriptInsightRequest.actionItemsPrompt.contains("Speaker 2"), false,
            "the owner examples do not offer a canonical speaker label"
        )
        try expect(
            TranscriptInsightRequest.actionItemsPrompt.contains("or null when nobody was named"), true,
            "an unnamed speaker still maps to null"
        )
    }

    // MARK: - Chunking

    private static func testChunker() throws {
        let short = "one\ntwo\nthree"
        try expect(
            TranscriptChunker.chunks(of: short, maxCharacters: 1_000), [short],
            "text that already fits comes back untouched"
        )

        let text = (1...20).map { "line-\($0) of the transcript" }.joined(separator: "\n")
        let chunks = TranscriptChunker.chunks(of: text, maxCharacters: 80)
        try expect(chunks.count > 1, true, "long text is split")
        try expect(
            chunks.joined(separator: "\n"), text,
            "rejoined chunks are the input exactly — nothing lost, nothing duplicated"
        )
        try expect(
            chunks.allSatisfy { $0.count <= 80 }, true,
            "no chunk exceeds the budget"
        )
        try expect(
            chunks.allSatisfy { !$0.hasPrefix("\n") && !$0.hasSuffix("\n") }, true,
            "chunks break on line boundaries, never inside one"
        )

        // Blank lines are part of the text and must survive the round trip.
        let withBlanks = "alpha\n\nbeta\n\ngamma\n\ndelta"
        try expect(
            TranscriptChunker.chunks(of: withBlanks, maxCharacters: 12).joined(separator: "\n"),
            withBlanks,
            "paragraph breaks survive chunking"
        )

        // A transcript written as one unbroken paragraph: the only cut available
        // is on spaces, and joining the pieces back with a space restores it.
        let paragraph = (1...40).map { "word\($0)" }.joined(separator: " ")
        let pieces = TranscriptChunker.chunks(of: paragraph, maxCharacters: 60)
        try expect(pieces.count > 1, true, "an over-long line is split on whitespace")
        try expect(pieces.joined(separator: " "), paragraph, "the words are all there, in order")
        try expect(pieces.allSatisfy { !$0.isEmpty }, true, "no empty pieces")

        // A single token longer than the whole budget is emitted rather than cut
        // mid-word or dropped — losing the recording's text is the worse failure.
        let oneWord = String(repeating: "x", count: 50)
        try expect(
            TranscriptChunker.chunks(of: oneWord, maxCharacters: 20), [oneWord],
            "an unsplittable line is still emitted"
        )
        try expect(
            TranscriptChunker.chunks(of: "a\n\(oneWord)\nb", maxCharacters: 20).contains(oneWord), true,
            "…even when it sits between lines that do fit"
        )
    }

    // MARK: - Summary layout

    /// The primary fixture is a verbatim excerpt of a live reply to
    /// `summaryPrompt`: the model groups the points by topic, as asked, and
    /// writes each topic as a bullet indistinguishable from the points under it.
    /// Reading that back as a flat list is how the grouping the prompt paid for
    /// becomes invisible to the reader.
    private static func testSummaryLayout() throws {
        let reply = """
        The standup covered the staging connection pool issue, the design diagram, EKS plan-share tests, and caught failures. ...

        - Connection pool issue:
        - Dan tracked it down yesterday: Hikari was capping connections in staging, so the nightly load run timed out.
        - Dan filed a ticket, and the ticketing team is picking it up this morning.

        - Design diagram:
        - Dan is still working through it.

        Open questions: Whether the caught failures are environmental; ...
        """
        let blocks = SummaryLayout.blocks(of: reply)
        try expect(
            blocks.map(\.shape),
            [.paragraph, .heading, .bullet, .bullet, .heading, .bullet, .paragraph],
            "a live reply's topic bullets are promoted over the points they group"
        )
        try expect(blocks.map(\.id), Array(0..<blocks.count), "ids are the position in the parsed run")
        try expect(
            blocks[1].text, "Connection pool issue",
            "the heading drops its colon — the styling carries it"
        )
        try expect(
            blocks[2].text,
            "Dan tracked it down yesterday: Hikari was capping connections in staging, so the nightly load run timed out.",
            "a colon inside a sentence leaves it a bullet, whole"
        )
        try expect(blocks[4].text, "Design diagram", "the second topic is a heading too")
        try expect(
            blocks[6].text,
            "Open questions: Whether the caught failures are environmental; ...",
            "the closing line is a sentence that opens with a label, not a label"
        )
        try expectNoTextLost(reply, blocks)

        // Both spellings, because the model follows a formatting instruction
        // only some of the time.
        try expect(
            SummaryLayout.blocks(of: "Connection pool issue:\n- Dan filed a ticket.").map(\.shape),
            [.heading, .bullet],
            "a bare topic line is a heading"
        )
        try expect(
            SummaryLayout.blocks(of: "- Connection pool issue:\n- Dan filed a ticket.").map(\.shape),
            [.heading, .bullet],
            "…and so is the same topic written as a bullet"
        )

        // Too long to be a label: a sentence that happens to end on its colon.
        let longLine = "- Dan walked through every place the pool is configured, and landed here:"
        try expect(
            SummaryLayout.blocks(of: "\(longLine)\n- Hikari was capping connections.").map(\.shape),
            [.bullet, .bullet],
            "a line too long to be a label stays a bullet"
        )
        try expect(
            SummaryLayout.blocks(of: "We shipped it. Next up:\n- Dan writes the changelog.").map(\.shape),
            [.paragraph, .bullet],
            "a colon behind a finished sentence is not a label"
        )

        let dangling = SummaryLayout.blocks(of: "The standup was short.\n\nConnection pool issue:")
        try expect(
            dangling.map(\.shape), [.paragraph, .paragraph],
            "a heading with nothing under it is not a grouping"
        )
        try expect(
            dangling[1].text, "Connection pool issue:",
            "…and gets its colon back rather than losing a character"
        )

        let stacked = SummaryLayout.blocks(of: "First topic:\nSecond topic:\n- Dan filed a ticket.")
        try expect(
            stacked.map(\.shape), [.paragraph, .heading, .bullet],
            "a heading landing straight on another heading demotes"
        )
        try expect(stacked[0].text, "First topic:", "the demoted one keeps its whole line")
        try expect(stacked[1].text, "Second topic", "the one that does group something is still a heading")

        // The prompt and the parser are two halves of one rule. If the prompt
        // stops asking for a heading line, only the bullet spelling above is
        // left holding the feature up.
        try expect(
            TranscriptInsightRequest.summaryPrompt.contains("its own plain line ending with a colon"),
            true,
            "the prompt asks for the shape the layout promotes"
        )
    }

    /// Nothing the model wrote may vanish between the reply and the pane. Every
    /// non-empty line has to turn up in some block, allowing only for the list
    /// marker and a heading's trailing colon being stripped.
    private static func expectNoTextLost(_ reply: String, _ blocks: [SummaryLayout.Block]) throws {
        for rawLine in reply.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            for marker in SummaryLayout.bulletMarkers where line.hasPrefix(marker) {
                line = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            }
            let core = line.hasSuffix(":") ? String(line.dropLast()) : line
            guard blocks.contains(where: { $0.text.contains(core) }) else {
                throw HarnessFailure(description: "no block carries \"\(core)\"")
            }
        }
    }
}
