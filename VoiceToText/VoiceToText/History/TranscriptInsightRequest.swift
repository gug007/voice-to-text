import Foundation

/// Everything the insight generator says to OpenAI and everything it reads back:
/// the two product prompts, the chat-completions payloads, and the parsing of
/// the action-item reply.
///
/// Pure and Foundation-only on purpose. The prompts *are* the feature — a
/// summary the user doesn't trust is worse than no summary — so they live
/// somewhere a harness can pin them down, away from the async machinery that
/// posts them (`TranscriptInsightGenerator`) and the HTTP round trip that
/// carries them (`ActionRunner.perform`).
nonisolated enum TranscriptInsightRequest {

    // MARK: - Prompts

    static let summaryPrompt = """
    You write the summary of a recorded conversation from its transcript.

    Write for someone who was not there and wants to know what happened in under a minute:
    - Open with one or two sentences saying what the conversation was about and where it landed.
    - Then take each topic in the order it was discussed: write the topic as its own plain line ending with a colon, not as a bullet, and put its points under it as short "- " lines.
    - Name a speaker only when the transcript names them (a "Kara:" label, or a name said aloud). Never invent a name for an unlabelled speaker.
    - Keep every decision, number, date, name and commitment exactly as stated. Do not round, guess, soften, or add anything the transcript does not say.
    - If something was left unresolved, end with a line starting "Open questions:".

    Write in the language the conversation is in. Plain text only — no markdown headings, no bold, no code fences, no preamble. Reply with only the summary.
    """

    static let actionItemsPrompt = """
    You extract the action items from a recorded conversation's transcript.

    An action item is something a person committed to do, was asked to do, or was assigned. A topic that was merely discussed, an opinion, and work that was already finished during the conversation are not action items.

    For each one:
    - "task": the action as one short imperative sentence, in the language of the conversation, carrying the detail needed to act on it.
    - "owner": the person or group responsible, exactly as the transcript names them ("Dan", "the ticketing team"), or null when nobody was named.
    - "due": when it is due, in the transcript's own words ("this morning", "before Friday", "next sprint"), or null when no timing was given.

    Never invent an owner, a deadline, or a task the transcript does not support. Keep the items in the order they came up. Return an empty list when the conversation produced no action items.
    """

    /// The reduce half of the chunked summary path: N part-summaries in, one
    /// summary out. It restates the output format because the model never sees
    /// the original transcript here, only the parts.
    static let summaryReducePrompt = """
    These are summaries of consecutive parts of ONE conversation, given in order.

    Merge them into a single summary of the whole conversation, in exactly the format the parts use: one or two opening sentences saying what it was about and where it landed, then each topic in the order it was discussed as its own plain line ending with a colon, not as a bullet, with its points under it as short "- " lines, and a final line starting "Open questions:" only if something was left unresolved.

    Remove repetition where two parts cover the same ground, keep the chronological order, and keep every decision, number, date, name and commitment exactly as the parts state it. Invent nothing that is not in them, and do not mention the parts, the split, or the transcript itself.

    Write in the language of the parts. Plain text only — no markdown headings, no bold, no code fences, no preamble. Reply with only the merged summary.
    """

    /// The system message for one request. `part` is 1-based and is supplied
    /// only on the chunked path, where the model is looking at a fragment and
    /// would otherwise open with "the call began…" for something that is
    /// actually the middle of a two-hour meeting.
    static func systemPrompt(for kind: InsightKind, part: (index: Int, total: Int)? = nil) -> String {
        let base: String
        switch kind {
        case .summary: base = summaryPrompt
        case .actionItems: base = actionItemsPrompt
        }
        guard let part else { return base }
        return """
        This is part \(part.index) of \(part.total) of a longer transcript — treat it as a fragment that starts and ends mid-conversation, cover only what this part contains, and do not open or close as if it were the whole conversation.

        \(base)
        """
    }

    // MARK: - Request bodies

    /// One chat-completions payload: model plus a system and a user message,
    /// with strict structured output for `.actionItems`.
    ///
    /// No `temperature` key. GPT-5-family models reject non-default values on
    /// chat completions (the same reason `ActionRunner.makeRequestBody` omits
    /// it), and the default is what these prompts were written against.
    ///
    /// Built through `JSONSerialization` rather than `Encodable` structs because
    /// the JSON Schema below is a literal document — its `"type"` fields hold
    /// *unions* like `["string","null"]`, which a tower of nested `Encodable`
    /// types would bury. Written as a dictionary it reads like the schema
    /// OpenAI documents, which is what it has to match exactly.
    static func makeRequestBody(
        kind: InsightKind,
        text: String,
        modelId: String,
        part: (index: Int, total: Int)? = nil
    ) throws -> Data {
        var payload: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "system", "content": systemPrompt(for: kind, part: part)],
                ["role": "user", "content": text],
            ],
        ]
        if kind == .actionItems {
            payload["response_format"] = actionItemsResponseFormat()
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// Combines the per-chunk summaries of one long transcript into a single
    /// summary. Plain text out, so no `response_format`.
    static func makeSummaryReduceBody(partialSummaries: [String], modelId: String) throws -> Data {
        let total = partialSummaries.count
        let joined = partialSummaries.enumerated()
            .map { "Part \($0.offset + 1) of \(total):\n\($0.element)" }
            .joined(separator: "\n\n")
        let payload: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "system", "content": summaryReducePrompt],
                ["role": "user", "content": joined],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// OpenAI strict structured output. `strict: true` only holds if every level
    /// lists *all* its properties in `required` and sets
    /// `additionalProperties: false` — an optional field is spelled as a nullable
    /// type, never as an absent one, which is why `owner` and `due` are
    /// `["string","null"]` and still required. The API rejects the request
    /// outright when this shape is wrong, so the harness asserts it.
    ///
    /// A function rather than a stored `static let`: `[String: Any]` isn't
    /// `Sendable`, and a global of a non-Sendable type is a Swift 6 error.
    private static func actionItemsResponseFormat() -> [String: Any] {
        let item: [String: Any] = [
            "type": "object",
            "properties": [
                "task": ["type": "string"],
                "owner": ["type": ["string", "null"]],
                "due": ["type": ["string", "null"]],
            ],
            "required": ["task", "owner", "due"],
            "additionalProperties": false,
        ]
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "items": [
                    "type": "array",
                    "items": item,
                ],
            ],
            "required": ["items"],
            "additionalProperties": false,
        ]
        return [
            "type": "json_schema",
            "json_schema": [
                "name": "action_items",
                "strict": true,
                "schema": schema,
            ],
        ]
    }

    // MARK: - Parsing the reply

    /// The action items as the model returned them, before they are given ids
    /// and stored.
    ///
    /// Separate from `ActionItem` so parsing stays pure: ids are minted by the
    /// generator, not by a parser a harness runs twice expecting equal results.
    struct ParsedActionItem: Equatable, Hashable, Sendable {
        let text: String
        let owner: String?
        let due: String?
    }

    /// Reads the action items out of a model reply.
    ///
    /// Structured output makes clean JSON the overwhelmingly likely answer, but
    /// this is a language model on the other end: it also survives a reply
    /// wrapped in a markdown fence, one with a sentence of preamble before the
    /// JSON, and — when the JSON is unsalvageable — a plain bulleted list.
    ///
    /// Returns nil only when nothing usable was found. An explicitly empty list
    /// is a *success*: "this conversation produced no action items" is a real
    /// and common answer, and must not be reported to the user as a failure.
    static func parseActionItems(from content: String) -> [ParsedActionItem]? {
        let unfenced = strippingCodeFence(content)
        for candidate in jsonCandidates(in: unfenced) {
            if let items = decodeActionItems(Data(candidate.utf8)) { return items }
        }
        return parseActionItemLines(unfenced)
    }

    /// Last-resort reader for a reply that ignored the schema and wrote a list.
    /// Understands "- ", "* ", "• " and "1. " / "1) " bullets, and pulls an owner
    /// out of a trailing "(Dan)" or a leading "Dan:".
    ///
    /// Both owner rules are deliberately narrow — a short prefix or parenthetical
    /// that also has to *read* like a name (see `looksLikeOwner`) — because the
    /// same shapes carry things that are not people: "Decision: ship on Friday"
    /// would claim "Decision" as a person, and "Send the deck (by Friday)" would
    /// turn a deadline into one. When the candidate does not pass, the line keeps
    /// its full text and gets no owner, which is the safe answer on a path only
    /// reached when the model has already ignored a strict schema.
    static func parseActionItemLines(_ content: String) -> [ParsedActionItem]? {
        var found: [ParsedActionItem] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let body = strippingBullet(line) else { continue }
            let (text, owner) = splittingOwner(from: body)
            guard !text.isEmpty else { continue }
            found.append(ParsedActionItem(text: text, owner: owner, due: nil))
        }
        return found.isEmpty ? nil : found
    }

    /// Merges parsed items from several chunks of one transcript, dropping
    /// repeats. The same commitment restated in the next chunk comes back with
    /// different capitalisation and punctuation ("Send the deck." / "send the
    /// deck"), so the key is folded and stripped; the first occurrence wins
    /// because it is the one in chronological order.
    ///
    /// The key is the task *and* the owner, not the task alone: in a standup three
    /// people routinely commit to "update the tracker", and collapsing those into
    /// one row owned by whoever spoke first deletes two real commitments — on
    /// exactly the long, chunked recordings where the checklist matters most. An
    /// unattributed restatement still folds into the named one (and back-fills the
    /// owner when it arrives the other way round), because "update the tracker"
    /// with nobody named is the same commitment said again, not a second person.
    ///
    /// A repeat never simply disappears: whatever the kept item is missing — an
    /// owner, a due date the second mention finally gave — is filled in from it.
    static func merging(_ items: [ParsedActionItem]) -> [ParsedActionItem] {
        /// Position in `merged` of "this task, this owner".
        var indexByKey: [String: Int] = [:]
        /// Position of the first mention of a task under any owner, and of the
        /// first mention that named nobody.
        var firstIndexByTask: [String: Int] = [:]
        var unattributedIndexByTask: [String: Int] = [:]
        var merged: [ParsedActionItem] = []

        /// Fills in the fields the kept item never had, keeping its own wording.
        func enrich(_ index: Int, with later: ParsedActionItem) {
            let kept = merged[index]
            guard kept.owner == nil || kept.due == nil else { return }
            merged[index] = ParsedActionItem(
                text: kept.text,
                owner: kept.owner ?? later.owner,
                due: kept.due ?? later.due
            )
        }

        for item in items {
            // A task written entirely in punctuation or emoji folds to an empty
            // key; keep it under its raw text rather than deleting it.
            let folded = dedupeKey(item.text)
            let task = folded.isEmpty
                ? item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                : folded
            guard !task.isEmpty else { continue }
            let ownerKey = dedupeKey(item.owner ?? "")
            let key = "\(task)|\(ownerKey)"

            if let index = indexByKey[key] {
                enrich(index, with: item)
                continue
            }
            if ownerKey.isEmpty, let index = firstIndexByTask[task] {
                enrich(index, with: item)
                continue
            }
            if !ownerKey.isEmpty, let index = unattributedIndexByTask[task] {
                enrich(index, with: item)
                indexByKey[key] = index
                unattributedIndexByTask[task] = nil
                continue
            }

            merged.append(item)
            let index = merged.count - 1
            indexByKey[key] = index
            if firstIndexByTask[task] == nil { firstIndexByTask[task] = index }
            if ownerKey.isEmpty, unattributedIndexByTask[task] == nil {
                unattributedIndexByTask[task] = index
            }
        }
        return merged
    }

    /// Re-checks, in a freshly generated list, the items the user had already
    /// ticked off in the previous one.
    ///
    /// Matched on the task text rather than the id: a regenerated list is a new
    /// set of ids by construction, so the text is the only thing the two versions
    /// share, and `dedupeKey` folds the capitalisation and trailing period a
    /// model varies between runs. An item the new list does not contain stays
    /// unchecked — a task nobody has seen before has not been done.
    ///
    /// Lives here, beside the dedupe rule it reuses and away from the store, so
    /// the one piece of user-entered data the insights layer holds is protected
    /// by something a harness can pin down.
    static func carryingDoneFlags(
        from previous: TranscriptActionItems?,
        onto fresh: TranscriptActionItems
    ) -> TranscriptActionItems {
        var doneKeys: Set<String> = []
        for item in previous?.items ?? [] where item.isDone {
            let key = dedupeKey(item.text)
            if !key.isEmpty { doneKeys.insert(key) }
        }
        guard !doneKeys.isEmpty else { return fresh }
        return TranscriptActionItems(
            items: fresh.items.map { item in
                let key = dedupeKey(item.text)
                guard !key.isEmpty, doneKeys.contains(key) else { return item }
                return item.marking(done: true)
            },
            generatedAt: fresh.generatedAt,
            modelId: fresh.modelId,
            sourceDigest: fresh.sourceDigest
        )
    }

    static func dedupeKey(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let withoutPunctuation = folded.unicodeScalars.filter {
            !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.symbols.contains($0)
        }
        return String(String.UnicodeScalarView(withoutPunctuation))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    // MARK: Parsing internals

    /// Unwraps a whole-message ``` fence, keeping the inside verbatim. Narrower
    /// than `ActionRunner.sanitize`: here the payload is JSON, so an opening
    /// fence with no closing one is still worth unwrapping — the model was cut
    /// off, and the brace scan below may still find a complete object.
    private static func strippingCodeFence(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The substrings worth trying as JSON: the whole reply first, then the span
    /// between the outermost braces (a reply with prose before or after it), then
    /// the outermost brackets (a bare array instead of the object).
    private static func jsonCandidates(in content: String) -> [Substring] {
        var candidates: [Substring] = [Substring(content)]
        for (open, close) in [(Character("{"), Character("}")), (Character("["), Character("]"))] {
            guard let first = content.firstIndex(of: open),
                  let last = content.lastIndex(of: close),
                  first < last else { continue }
            let span = content[first...last]
            guard span != candidates[0] else { continue }
            // A span lifted out of prose is only worth decoding when it actually
            // holds objects. Otherwise a sentence that happens to end in "[]"
            // would decode as "no action items" and swallow the bulleted list
            // written above it, which the line reader would have read fine.
            guard span.contains("{") else { continue }
            candidates.append(span)
        }
        return candidates
    }

    private static func decodeActionItems(_ data: Data) -> [ParsedActionItem]? {
        /// Tolerates the near-miss key names a model reaches for when it
        /// paraphrases the schema instead of following it.
        struct Wire: Decodable {
            let task: String?
            let text: String?
            let action: String?
            let owner: String?
            let who: String?
            let due: String?
            let when: String?
        }
        struct Envelope: Decodable {
            let items: [Wire]?
            let actionItems: [Wire]?

            enum CodingKeys: String, CodingKey {
                case items
                case actionItems = "action_items"
            }
        }

        let decoder = JSONDecoder()
        let wires: [Wire]
        if let envelope = try? decoder.decode(Envelope.self, from: data),
           let list = envelope.items ?? envelope.actionItems {
            wires = list
        } else if let list = try? decoder.decode([Wire].self, from: data) {
            wires = list
        } else {
            return nil
        }

        let parsed = wires.compactMap { wire -> ParsedActionItem? in
            let text = firstNonEmpty(wire.task, wire.text, wire.action)
            guard let text else { return nil }
            return ParsedActionItem(
                text: text,
                owner: firstNonEmpty(wire.owner, wire.who),
                due: firstNonEmpty(wire.due, wire.when)
            )
        }
        // Every property of `Wire` is optional, so a list of objects that names
        // none of the keys above still decodes — and would come back as an empty
        // *success*, telling the user the meeting committed nobody to anything
        // while the model had actually listed the work under `"item"` /
        // `"description"`. A list that decoded but yielded nothing usable is a
        // paraphrased schema, so it falls through to the next candidate and the
        // line reader. Only a genuinely empty list still reports "no items".
        guard parsed.isEmpty == wires.isEmpty else { return nil }
        return parsed
    }

    /// The first value that is actually a value. Models emit `"none"`, `"N/A"`
    /// and the *string* `"null"` for a field they were told to leave null, and
    /// none of those should reach the UI as an owner's name.
    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { continue }
            let lowered = trimmed.lowercased()
            if lowered == "null" || lowered == "none" || lowered == "n/a" || lowered == "unknown" { continue }
            return trimmed
        }
        return nil
    }

    /// The text after a list marker, or nil when the line isn't a list item.
    private static func strippingBullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "• ", "– ", "— "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        // "1. " / "12) " — digits, one separator, then the text.
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let separator = rest.first, separator == "." || separator == ")" else { return nil }
        let text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func splittingOwner(from body: String) -> (text: String, owner: String?) {
        // Trailing "(Dan)" — the shape a model uses when it appends the owner.
        if body.hasSuffix(")"), let open = body.lastIndex(of: "(") {
            let inside = body[body.index(after: open)..<body.index(before: body.endIndex)]
                .trimmingCharacters(in: .whitespaces)
            let text = String(body[body.startIndex..<open]).trimmingCharacters(in: .whitespaces)
            if !inside.isEmpty, inside.count <= 40, !text.isEmpty, looksLikeOwner(inside) {
                return (text, inside)
            }
        }
        // Leading "Dan:" — a name, not a label, only under the narrow rule in
        // `parseActionItemLines`' doc comment.
        if let colon = body.firstIndex(of: ":") {
            let prefix = String(body[body.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(body[body.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let words = prefix.split(whereSeparator: \.isWhitespace)
            let isPlainName = !prefix.isEmpty
                && words.count <= 3
                && prefix.count <= 32
                && prefix.rangeOfCharacter(from: CharacterSet(charactersIn: ".,;!?()")) == nil
            if isPlainName, !rest.isEmpty, looksLikeOwner(prefix) {
                return (rest, prefix)
            }
        }
        return (body, nil)
    }

    /// Whether a short prefix or parenthetical could plausibly be a person or a
    /// team, rather than one of the other things that sit in exactly the same
    /// place.
    ///
    /// Three shapes get rejected, because each one produces a chip with a person
    /// icon naming somebody who was never in the meeting: the section labels a
    /// model writes when it stops following the format ("Decision:", "Note:",
    /// "Open questions:"), a parenthetical that is really timing ("(by Friday)",
    /// "(next sprint)") or a status ("(blocked on QA)"), and anything carrying a
    /// digit, which a name essentially never does but a date or a quarter always
    /// does. The list is not exhaustive and does not need to be — this only runs
    /// after the model has already ignored a strict schema, and every rejection
    /// falls back to keeping the line whole with no owner.
    private static func looksLikeOwner(_ candidate: String) -> Bool {
        let lowered = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !lowered.isEmpty else { return false }
        guard !lowered.contains(where: \.isNumber) else { return false }
        guard !labelPhrases.contains(lowered) else { return false }
        // The first word decides the rest: "blocked on QA" and "by Friday" are
        // not phrases anyone can enumerate, but their opening word gives them
        // away just as reliably as the bare label does.
        let firstWord = lowered.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? lowered
        return !labelPhrases.contains(firstWord) && !timingWords.contains(firstWord)
    }

    /// Candidates that are a section heading or a status, not a person.
    private static let labelPhrases: Set<String> = [
        "decision", "decisions", "note", "notes", "open question", "open questions",
        "owner", "deadline", "action", "actions", "action item", "action items",
        "next step", "next steps", "todo", "to do", "follow-up", "follow up",
        "blocked", "blocker", "status", "risk", "risks", "summary", "pending", "waiting",
    ]

    /// Opening words that make the candidate a time, not a person. Ordinary names
    /// that double as month names ("May") are lost to this, which is the cheap
    /// direction to be wrong in: the item keeps its text and simply shows no
    /// owner chip.
    private static let timingWords: Set<String> = [
        "by", "before", "after", "due", "until", "till", "eta", "asap", "end",
        "this", "next", "today", "tomorrow", "tonight", "later", "within", "during",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december",
    ]
}

/// Splits a transcript that is too long for one request into pieces the model
/// can actually read.
///
/// Splits on line boundaries only. A chunk that ends mid-sentence makes the
/// model summarize a half-thought and, worse, invent the other half; a
/// paragraph break is where a conversation already changes subject, so it is
/// the cheapest cut that keeps each part coherent.
nonisolated enum TranscriptChunker {
    /// Greedy grouping of whole lines. Chunks rejoined with "\n" reproduce the
    /// input exactly — nothing is dropped, nothing is duplicated — except where
    /// the whitespace fallback below had to break a single over-long line, where
    /// one space becomes a newline.
    ///
    /// Text that already fits comes back as `[text]` untouched, so the caller
    /// can treat "one chunk" as "no chunking happened".
    static func chunks(of text: String, maxCharacters: Int) -> [String] {
        guard maxCharacters > 0, text.count > maxCharacters else { return [text] }

        var chunks: [String] = []
        // Lines of the chunk being filled. An array rather than a joined string
        // so a blank line in the middle of the transcript survives — testing a
        // joined buffer for emptiness would silently swallow it.
        var current: [String] = []
        var currentCount = 0

        for line in text.components(separatedBy: "\n") {
            // +1 for the newline that will rejoin this line to the previous one.
            let projected = current.isEmpty ? line.count : currentCount + 1 + line.count
            if !current.isEmpty, projected > maxCharacters {
                chunks.append(current.joined(separator: "\n"))
                current = []
                currentCount = 0
            }
            if line.count <= maxCharacters {
                currentCount = current.isEmpty ? line.count : currentCount + 1 + line.count
                current.append(line)
                continue
            }
            // One line longer than the whole budget — a transcript written as a
            // single unbroken paragraph. Emitting it whole would fail the
            // request, and dropping it would lose the recording's content, so
            // fall back to cutting on spaces.
            if !current.isEmpty {
                chunks.append(current.joined(separator: "\n"))
                current = []
                currentCount = 0
            }
            chunks.append(contentsOf: splittingOnWhitespace(line, maxCharacters: maxCharacters))
        }

        if !current.isEmpty { chunks.append(current.joined(separator: "\n")) }
        return chunks.isEmpty ? [text] : chunks
    }

    /// Greedy grouping of space-separated tokens; the pieces rejoined with a
    /// single space reproduce the line. A single token longer than the budget is
    /// still emitted whole rather than cut mid-word — losing it would be worse
    /// than one oversized request.
    private static func splittingOnWhitespace(_ line: String, maxCharacters: Int) -> [String] {
        var pieces: [String] = []
        var current: [Substring] = []
        var currentCount = 0
        for token in line.split(separator: " ", omittingEmptySubsequences: false) {
            let projected = current.isEmpty ? token.count : currentCount + 1 + token.count
            if !current.isEmpty, projected > maxCharacters {
                pieces.append(current.joined(separator: " "))
                current = []
                currentCount = 0
            }
            currentCount = current.isEmpty ? token.count : currentCount + 1 + token.count
            current.append(token)
        }
        if !current.isEmpty { pieces.append(current.joined(separator: " ")) }
        return pieces.isEmpty ? [line] : pieces
    }
}


/// Pure plain-text → blocks layout for a summary: the shape of the model's
/// reply, read back out of it.
///
/// It lives here, beside `summaryPrompt`, rather than beside the SwiftUI that
/// draws it, because these are not styling rules — they are product logic about
/// what the model writes, the other half of the prompt that asked for it. A file
/// importing SwiftUI cannot be compiled by a standalone harness, so over there
/// the rules could only be checked by reading them; here the harness pins them
/// to a real reply.
nonisolated enum SummaryLayout {

    struct Block: Identifiable, Hashable, Sendable {
        enum Shape: Hashable, Sendable { case paragraph, bullet, heading }
        /// Position in the parsed run. Stable for one string, which is all a
        /// `ForEach` over an immutable summary needs.
        let id: Int
        let shape: Shape
        let text: String
    }

    /// The three markers models actually emit for a list item. A bare "-" with
    /// no space is left alone on purpose: it is far more often a dash inside a
    /// sentence than a bullet.
    static let bulletMarkers = ["- ", "* ", "• "]

    /// The longest line still readable as a label rather than as a sentence that
    /// happens to end in a colon.
    static let headingCharacterLimit = 60

    static func blocks(of text: String) -> [Block] {
        // Shape and text, plus the line the text came from: a heading that turns
        // out to be dangling is demoted back to a paragraph and has to get its
        // colon back.
        var draft: [(shape: Block.Shape, text: String, raw: String)] = []
        var paragraphLines: [String] = []

        // Consecutive non-bullet lines are one paragraph: models hard-wrap
        // prose, and rendering each wrapped line as its own block would double
        // every gap in the pane.
        func flushParagraph() {
            let joined = paragraphLines
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            paragraphLines.removeAll()
            guard !joined.isEmpty else { return }
            draft.append((shape: .paragraph, text: joined, raw: joined))
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                continue
            }
            let marker = bulletMarkers.first(where: { line.hasPrefix($0) })
            let body = marker
                .map { String(line.dropFirst($0.count)).trimmingCharacters(in: .whitespaces) }
                ?? line
            guard !body.isEmpty else { continue }

            if let label = headingLabel(in: body) {
                flushParagraph()
                draft.append((shape: .heading, text: label, raw: body))
            } else if marker != nil {
                flushParagraph()
                draft.append((shape: .bullet, text: body, raw: body))
            } else {
                paragraphLines.append(line)
            }
        }
        flushParagraph()

        return draft.enumerated().map { index, entry in
            // A label with nothing under it groups nothing; it is a stray line.
            // Give it its colon back and let it read as prose rather than
            // leaving a heading hanging over the next topic — or over the end.
            let isLast = index == draft.count - 1
            let nextIsHeading = !isLast && draft[index + 1].shape == .heading
            let dangling = entry.shape == .heading && (isLast || nextIsHeading)
            return Block(
                id: index,
                shape: dangling ? .paragraph : entry.shape,
                text: dangling ? entry.raw : entry.text
            )
        }
    }

    /// The label of a topic heading, or nil when the line is not one. Takes the
    /// line with any bullet marker already stripped, which is what promotes
    /// *both* spellings: the bare "Connection pool issue:" line `summaryPrompt`
    /// asks for, and the "- Connection pool issue:" bullet the model writes
    /// anyway. A model ignoring one formatting instruction is the normal case,
    /// not the exception, so the reader cannot depend on the prompt being
    /// followed — the grouping has to survive either spelling.
    ///
    /// Three things keep a sentence from being promoted. The colon has to end
    /// the line, so "Open questions: Whether the caught failures are
    /// environmental" stays prose. The line has to be short enough to be a
    /// label. And it cannot contain a period, which is the tell that the colon
    /// is punctuation inside a sentence — "Dan tracked it down yesterday:
    /// Hikari was capping connections." is a point, not a heading.
    ///
    /// The trailing colon is dropped from the label: the styling carries it, and
    /// a heading drawn with one would read as a line that lost its ending.
    static func headingLabel(in body: String) -> String? {
        guard body.hasSuffix(":"), body.count <= headingCharacterLimit else { return nil }
        let label = String(body.dropLast()).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !label.contains(".") else { return nil }
        return label
    }
}
