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

@main
struct ActionRunnerHarness {
    static func main() throws {
        try testRequestBody()
        try testParseResponse()
        try testSanitize()
        try testErrorMessage()
        try testRequestErrorClassification()
        try testReviewActionFailureCopy()
        try testTimeoutScaling()
        try testCatalog()
        try testActionCodableRoundTrip()
        try testCatalogSync()
        print("ActionRunnerHarness: all checks passed")
    }

    private static func testRequestBody() throws {
        struct Message: Decodable {
            let role: String
            let content: String
        }
        struct Payload: Decodable {
            let model: String
            let messages: [Message]
            let temperature: Double?
        }

        let data = try ActionRunner.makeRequestBody(
            instruction: "Translate to English.",
            text: "hola mundo",
            modelId: ActionRunner.modelId
        )
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        try expect(payload.model, ActionRunner.modelId, "request carries the model id")
        try expect(
            payload.temperature, nil,
            "no temperature override — GPT-5-family models reject non-default values"
        )
        try expect(payload.messages.count, 2, "request has system + user messages")
        try expect(payload.messages[0].role, "system", "first message is the system prompt")
        try expect(
            payload.messages[0].content.contains("Translate to English."),
            true,
            "system prompt embeds the action instruction"
        )
        try expect(payload.messages[1].role, "user", "second message is the transcript")
        try expect(payload.messages[1].content, "hola mundo", "transcript passes through unmodified")
    }

    private static func testParseResponse() throws {
        let valid = Data("""
        {"choices":[{"message":{"role":"assistant","content":"hello world"}}]}
        """.utf8)
        try expect(ActionRunner.parseResponse(valid), "hello world", "valid body parses")

        let empty = Data(#"{"choices":[]}"#.utf8)
        try expect(ActionRunner.parseResponse(empty), nil, "empty choices yields nil")

        let garbage = Data("not json".utf8)
        try expect(ActionRunner.parseResponse(garbage), nil, "malformed body yields nil")
    }

    private static func testSanitize() throws {
        try expect(
            ActionRunner.sanitize("  hello world \n"),
            "hello world",
            "plain output is trimmed"
        )
        try expect(
            ActionRunner.sanitize("```\nhello world\n```"),
            "hello world",
            "whole-message fence unwraps"
        )
        try expect(
            ActionRunner.sanitize("```text\nline one\nline two\n```"),
            "line one\nline two",
            "language-tagged fence unwraps and keeps inner newlines"
        )
        try expect(
            ActionRunner.sanitize("use `let` not `var`"),
            "use `let` not `var`",
            "inline backticks are left alone"
        )
        try expect(
            ActionRunner.sanitize("```starts fenced but does not end"),
            "```starts fenced but does not end",
            "unterminated fence is left alone"
        )
        try expect(
            ActionRunner.sanitize("```bash\nls\n```\nThen run:\n```bash\npwd\n```"),
            "```bash\nls\n```\nThen run:\n```bash\npwd\n```",
            "multi-block output with interior fences is left alone"
        )
    }

    private static func testErrorMessage() throws {
        let envelope = Data(#"{"error":{"message":"Rate limit reached"}}"#.utf8)
        try expect(
            ActionRunner.errorMessage(from: envelope),
            "Rate limit reached",
            "OpenAI error envelope is decoded"
        )
        let raw = Data("plain failure".utf8)
        try expect(
            ActionRunner.errorMessage(from: raw),
            "plain failure",
            "non-envelope bodies fall back to raw text"
        )
        try expect(
            ActionRunner.errorMessage(from: Data(" \n".utf8)),
            nil,
            "an empty body leaves the caller's HTTP status to say it"
        )
    }

    private static func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: ActionRunner.endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private static func body(code: String?, message: String) -> Data {
        let codeField = code.map { #","code":"\#($0)""# } ?? ""
        return Data(#"{"error":{"message":"\#(message)"\#(codeField)}}"#.utf8)
    }

    private static func testRequestErrorClassification() throws {
        let quota = ActionRunner.httpError(
            response(429),
            body: body(code: "insufficient_quota", message: "You exceeded your current quota.")
        )
        try expect(quota.failure, .quotaExhausted, "429 insufficient_quota is an exhausted balance, not a rate limit")
        try expect(
            quota.localizedDescription,
            "OpenAI: You exceeded your current quota.",
            "the description stays the sentence insight tabs always showed"
        )

        let limited = ActionRunner.httpError(
            response(429, headers: ["Retry-After": "20"]),
            body: body(code: "rate_limit_exceeded", message: "Rate limit reached")
        )
        try expect(limited.failure, .rateLimited(retryAfter: 20), "plain 429 is a rate limit with its Retry-After")

        try expect(
            ActionRunner.httpError(response(402), body: Data()).failure,
            .quotaExhausted,
            "402 is an exhausted balance"
        )
        try expect(
            ActionRunner.httpError(response(401), body: body(code: "invalid_api_key", message: "Incorrect API key")).failure,
            .unauthorized,
            "401 is a refused key"
        )
        try expect(
            ActionRunner.httpError(response(503), body: Data()).failure,
            .server,
            "5xx is the provider's own trouble"
        )
        let bare = ActionRunner.httpError(response(400), body: Data())
        try expect(bare.failure, .other, "an unexplained 400 stays unclassified")
        try expect(bare.detail, "OpenAI: HTTP 400", "an empty body falls back to the status")

        let timeout = ActionRequestError(cause: .transport(.timedOut), detail: "Network error: The request timed out.")
        try expect(timeout.isTimeout, true, "a timed-out request is told apart from other transport errors")
        try expect(timeout.failure, .other, "a timeout is not reported as being offline")

        let offline = ActionRequestError(cause: .transport(.notConnectedToInternet), detail: "Network error: offline")
        try expect(offline.isTimeout, false, "no connection is not a timeout")
        try expect(offline.failure, .offline, "no connection is offline")
    }

    private static func testReviewActionFailureCopy() throws {
        let quota = ReviewActionFailure(
            actionName: "Improve prompt",
            error: ActionRunner.httpError(
                response(429),
                body: body(code: "insufficient_quota", message: "You exceeded your current quota.")
            )
        )
        try expect(
            quota.message,
            "Couldn't run “Improve prompt”: OpenAI says your account is out of credit. Your transcript is unchanged — Paste still works.",
            "an exhausted balance names the action and says the transcript is safe"
        )
        try expect(quota.keyAction, nil, "no key fix is offered for a balance")

        let unauthorized = ReviewActionFailure(
            actionName: "Improve prompt",
            error: ActionRunner.httpError(response(401), body: body(code: "invalid_api_key", message: "Incorrect API key"))
        )
        try expect(
            unauthorized.message,
            "Couldn't run “Improve prompt”: OpenAI didn't accept your API key. Your transcript is unchanged.",
            "a refused key says so"
        )
        try expect(unauthorized.keyAction, .check, "a refused key offers Check API Key")

        let noKey = ReviewActionFailure(actionName: "Improve prompt", error: ActionRunnerError.noAPIKey)
        try expect(noKey.keyAction, .add, "a missing key offers Add API Key")

        let longTimeout = ReviewActionFailure(
            actionName: "Improve prompt",
            error: ActionRequestError(
                cause: .transport(.timedOut),
                detail: "Network error: The request timed out.",
                timeout: ActionRunner.timeout(forCharacterCount: 5_000)
            )
        )
        try expect(
            longTimeout.message,
            "“Improve prompt” took too long for this much text. Your transcript is unchanged.",
            "a timeout the text stretched blames the length"
        )

        let stalledMessage =
            "Couldn't run “Fix grammar”: OpenAI didn't answer in time — check your connection. Your transcript is unchanged."
        let shortTimeout = ReviewActionFailure(
            actionName: "Fix grammar",
            error: ActionRequestError(
                cause: .transport(.timedOut),
                detail: "Network error: The request timed out.",
                timeout: ActionRunner.timeout(forCharacterCount: 0)
            )
        )
        try expect(
            shortTimeout.message,
            stalledMessage,
            "a short text that ran out the base minute points at the connection, not the length"
        )
        let sentenceTimeout = ReviewActionFailure(
            actionName: "Fix grammar",
            error: ActionRequestError(
                cause: .transport(.timedOut),
                detail: "Network error: The request timed out.",
                timeout: ActionRunner.timeout(forCharacterCount: "Can you send me the notes from this morning's call.".count)
            )
        )
        try expect(
            sentenceTimeout.message,
            stalledMessage,
            "a one-sentence text, which stretches the limit by a second, points at the connection"
        )
        let thresholdTimeout = ReviewActionFailure(
            actionName: "Fix grammar",
            error: ActionRequestError(
                cause: .transport(.timedOut),
                detail: "Network error: The request timed out.",
                timeout: ActionRunner.timeout(forCharacterCount: 1_500)
            )
        )
        try expect(
            thresholdTimeout.message,
            "“Fix grammar” took too long for this much text. Your transcript is unchanged.",
            "a text that stretched the limit by half a minute blames the length"
        )
        try expect(
            ActionRunner.timeoutReflectsLength(ActionRunner.timeout(forCharacterCount: 1_000)),
            false,
            "a few paragraphs' extra seconds are not blamed"
        )
        let unknownTimeout = ReviewActionFailure(
            actionName: "Fix grammar",
            error: ActionRequestError(cause: .transport(.timedOut), detail: "Network error: The request timed out.")
        )
        try expect(unknownTimeout.message, stalledMessage, "a timeout of unknown length does not blame the text")

        let limited = ReviewActionFailure(
            actionName: "Translate",
            error: ActionRequestError(
                cause: .http(status: 429, retryAfter: 20, apiCode: nil),
                detail: "OpenAI: Rate limit reached"
            )
        )
        try expect(
            limited.message,
            "Couldn't run “Translate”: OpenAI is rate-limiting requests, try again in 20s. Your transcript is unchanged — Paste still works.",
            "a rate limit says when to try again"
        )

        let other = ReviewActionFailure(
            actionName: "Translate",
            error: ActionRequestError(
                cause: .http(status: 400, retryAfter: nil, apiCode: "model_not_found"),
                detail: "OpenAI: The model does not exist."
            )
        )
        try expect(
            other.message,
            "Couldn't run “Translate” (OpenAI: The model does not exist). Your transcript is unchanged — Paste still works.",
            "an unclassified error keeps its own words, bracketed"
        )

        let lost = ReviewActionFailure(
            actionName: "Translate",
            error: ActionRequestError(
                cause: .transport(.networkConnectionLost),
                detail: "Network error: The network connection was lost."
            )
        )
        try expect(
            lost.message,
            "Couldn't run “Translate” (Network error: The network connection was lost). Your transcript is unchanged — Paste still works.",
            "a dropped connection is not called offline"
        )

        let empty = ReviewActionFailure(actionName: "Translate", error: ActionRunnerError.emptyResult)
        try expect(
            empty.message,
            "“Translate” came back empty. Your transcript is unchanged — Paste still works.",
            "an empty reply says the transcript is safe"
        )

        let longName = String(repeating: "a", count: 60)
        let clipped = ReviewActionFailure(actionName: longName, error: ActionRunnerError.emptyResult)
        try expect(
            clipped.message.hasPrefix("“\(String(repeating: "a", count: ReviewActionFailure.longestNameShown - 1))…”"),
            true,
            "a long action name is clipped so the reassurance still fits"
        )

        let longBody = String(repeating: "x", count: 400)
        let clippedDetail = ReviewActionFailure(
            actionName: "Translate",
            error: ActionRequestError(cause: .http(status: 400, retryAfter: nil, apiCode: nil), detail: longBody)
        )
        try expect(
            clippedDetail.message.hasSuffix("Your transcript is unchanged — Paste still works."),
            true,
            "a long error body is clipped so the reassurance still fits"
        )
        try expect(
            ReviewActionFailure.clipped("line one\n\n  line two  ", to: 40),
            "line one line two",
            "an error body is folded onto one line"
        )
    }

    private static func testTimeoutScaling() throws {
        try expect(ActionRunner.timeout(forCharacterCount: 0), 60, "a short rewrite keeps the 60s cap")
        try expect(ActionRunner.timeout(forCharacterCount: 200), 64, "the cap grows with the text")
        try expect(ActionRunner.timeout(forCharacterCount: 5_000), 160, "a long prompt gets minutes, not seconds")
        try expect(
            ActionRunner.timeout(forCharacterCount: 1_000_000),
            ActionRunner.maxActionTimeout,
            "the cap never exceeds the long-call limit"
        )
        try expect(ActionRunner.maxActionTimeout, 240, "the long-call limit matches insight requests'")
    }

    private static func testCatalog() throws {
        try expect(ActionCatalog.defaults.isEmpty, false, "default actions exist for first-launch seeding")
        for template in ActionCatalog.defaults {
            try expect(template.name.isEmpty, false, "template has a name")
            try expect(template.prompt.isEmpty, false, "template '\(template.name)' has a prompt")
        }
        let names = ActionCatalog.defaults.map(\.name)
        try expect(Set(names).count, names.count, "default template names are unique")

        let action = ActionCatalog.defaults[0].makeAction()
        let again = ActionCatalog.defaults[0].makeAction()
        try expect(action.id == again.id, false, "each seeded action gets its own identity")
        try expect(action.isEnabled, true, "explicitly added templates start enabled")
        try expect(
            ActionCatalog.defaults[0].makeAction(isEnabled: false).isEnabled,
            false,
            "first-launch seeding can create disabled actions"
        )
    }

    private static func testActionCodableRoundTrip() throws {
        let action = DictationAction(name: "Translate", prompt: "Translate the text.", isEnabled: false)
        let data = try JSONEncoder().encode([action])
        let decoded = try JSONDecoder().decode([DictationAction].self, from: data)
        try expect(decoded, [action], "actions round-trip through JSON persistence, keeping isEnabled")

        // Lists persisted before per-action toggles have no isEnabled key;
        // actions are opt-in, so they must decode as disabled.
        let legacy = Data("""
        [{"id":"00000000-0000-0000-0000-000000000001","name":"Old","prompt":"Old prompt."}]
        """.utf8)
        let migrated = try JSONDecoder().decode([DictationAction].self, from: legacy)
        try expect(migrated.count, 1, "legacy list decodes")
        try expect(migrated[0].isEnabled, false, "legacy actions without the key decode as disabled")
        try expect(migrated[0].templateId, nil, "legacy actions carry no template link")
        try expect(migrated[0].isUserEdited, false, "legacy actions count as untouched")
    }

    private static func testCatalogSync() throws {
        let templates = [
            ActionCatalog.Template(id: "t-one", name: "One", prompt: "First prompt."),
            ActionCatalog.Template(id: "t-two", name: "Two", prompt: "Second prompt."),
        ]

        // Legacy adoption: a stored action matching a template by name gets
        // linked, then receives the template's prompt update.
        let legacyRow = DictationAction(name: "One", prompt: "Old prompt.", isEnabled: true)
        var outcome = ActionCatalogSync.sync(
            stored: [legacyRow],
            seededTemplateIds: nil,
            templates: templates
        )
        try expect(outcome.actions[0].templateId, "t-one", "name-matching legacy row adopts the template id")
        try expect(outcome.actions[0].prompt, "First prompt.", "linked row picks up the catalog prompt")
        try expect(outcome.actions[0].isEnabled, true, "sync never touches the toggle")
        try expect(outcome.actions.count, 1, "missing record treats current templates as already offered")
        try expect(outcome.changed, true, "adoption and record creation persist")

        // Template updates flow into linked, non-edited rows; user-edited
        // rows and hand-written rows are untouched; deleted templates stay
        // deleted; brand-new templates are appended disabled.
        let linked = DictationAction(name: "Stale", prompt: "Stale.", isEnabled: true, templateId: "t-one")
        let edited = DictationAction(name: "Mine", prompt: "Mine.", isEnabled: true, templateId: "t-two", isUserEdited: true)
        let custom = DictationAction(name: "Custom", prompt: "Custom.")
        let newTemplates = templates + [
            ActionCatalog.Template(id: "t-three", name: "Three", prompt: "Third prompt."),
        ]
        outcome = ActionCatalogSync.sync(
            stored: [linked, edited, custom],
            seededTemplateIds: ["t-one", "t-two", "t-gone"],
            templates: newTemplates
        )
        try expect(outcome.actions[0].name, "One", "linked row tracks the template rename")
        try expect(outcome.actions[1].name, "Mine", "user-edited row is never overwritten")
        try expect(outcome.actions[2].name, "Custom", "hand-written row is never overwritten")
        try expect(outcome.actions.count, 4, "new template is appended once")
        try expect(outcome.actions[3].templateId, "t-three", "appended row links to its template")
        try expect(outcome.actions[3].isEnabled, false, "appended row starts disabled")
        try expect(
            outcome.seededTemplateIds.contains("t-gone"), true,
            "seeded record keeps ids of templates that left the catalog"
        )

        // Stable state: running sync again changes nothing.
        let again = ActionCatalogSync.sync(
            stored: outcome.actions,
            seededTemplateIds: outcome.seededTemplateIds,
            templates: newTemplates
        )
        try expect(again.changed, false, "sync is idempotent once reconciled")
    }
}
