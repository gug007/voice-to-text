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
        try testCatalog()
        try testActionCodableRoundTrip()
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
    }
}
