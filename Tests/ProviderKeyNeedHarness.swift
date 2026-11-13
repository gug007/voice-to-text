import Foundation

struct ProviderKeyNeedHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw ProviderKeyNeedHarnessFailure(description: message)
    }
}

@main
struct ProviderKeyNeedHarness {
    static func main() throws {
        try aLocalOnlyUserSeesNoWarnings()
        try theDictationModelNeedsItsProvider()
        try conversationsNeedTheirProvider()
        try theSecondShortcutNeedsItsProvider()
        try actionsNeedOpenAI()
        try aKeyEndsTheNeed()
        try theReasonsPrioritise()
        print("Provider key need harness passed")
    }

    private static func need(
        _ provider: CloudProvider,
        hasKey: Bool = false,
        dictation: CloudProvider? = nil,
        name: String? = nil,
        conversation: CloudProvider? = nil,
        second: CloudProvider? = nil,
        actions: Int = 0
    ) -> ProviderKeyNeed {
        ProviderKeyNeed.evaluate(
            provider: provider,
            hasKey: hasKey,
            dictationModelProvider: dictation,
            dictationModelName: name,
            conversationModelProvider: conversation,
            secondShortcutModelProvider: second,
            enabledActionCount: actions
        )
    }

    private static func theSecondShortcutNeedsItsProvider() throws {
        let groq = need(.groq, second: .groq)
        try expect(groq == .needed(.secondShortcut), "the second shortcut's model's provider is needed")
        try expect(groq.statusText == "Needed for the second shortcut", "and says so")
        try expect(need(.openAI, second: .groq) == .neutral, "other providers stay neutral")
        try expect(need(.groq, hasKey: true, second: .groq) == .neutral, "a key ends the need")
    }

    private static func aLocalOnlyUserSeesNoWarnings() throws {
        for provider in CloudProvider.allCases {
            try expect(need(provider) == .neutral, "\(provider) without a key and unused is neutral")
            try expect(need(provider).statusText == nil, "and has no reason to show")
        }
    }

    private static func theDictationModelNeedsItsProvider() throws {
        let groq = need(.groq, dictation: .groq, name: "Whisper Large v3 Turbo")
        try expect(groq == .needed(.dictationModel(name: "Whisper Large v3 Turbo")), "the dictation model's provider is needed")
        try expect(groq.statusText == "Needed for Whisper Large v3 Turbo", "and says for which model")
        try expect(need(.openAI, dictation: .groq, name: "Whisper Large v3 Turbo") == .neutral, "other providers stay neutral")
    }

    private static func conversationsNeedTheirProvider() throws {
        let eleven = need(.elevenLabs, conversation: .elevenLabs)
        try expect(eleven == .needed(.conversations), "the conversation model's provider is needed")
        try expect(eleven.statusText == "Needed for conversations", "and says so")
        try expect(need(.openAI, conversation: nil) == .neutral, "a local conversation model needs no key")
    }

    private static func actionsNeedOpenAI() throws {
        try expect(need(.openAI, actions: 2) == .needed(.actions), "enabled Actions need OpenAI")
        try expect(need(.openAI, actions: 2).statusText == "Needed for Actions", "and say so")
        try expect(need(.openAI, actions: 0) == .neutral, "with none enabled, OpenAI is neutral")
        try expect(need(.groq, actions: 3) == .neutral, "Actions never need another provider")
        try expect(need(.elevenLabs, actions: 3) == .neutral, "nor ElevenLabs")
    }

    private static func aKeyEndsTheNeed() throws {
        try expect(
            need(.openAI, hasKey: true, dictation: .openAI, name: "GPT Transcribe", conversation: .openAI, actions: 4) == .neutral,
            "a provider with its key is never warned about here"
        )
    }

    private static func theReasonsPrioritise() throws {
        try expect(
            need(.openAI, dictation: .openAI, name: "GPT Transcribe", conversation: .openAI, actions: 1)
                == .needed(.dictationModel(name: "GPT Transcribe")),
            "the dictation model is the reason first"
        )
        try expect(need(.openAI, conversation: .openAI, actions: 1) == .needed(.conversations), "then conversations, then Actions")
        try expect(
            need(.openAI, dictation: .openAI, name: "GPT Transcribe", second: .openAI) == .needed(.dictationModel(name: "GPT Transcribe")),
            "the dictation model comes before the second shortcut"
        )
        try expect(need(.openAI, conversation: .openAI, second: .openAI) == .needed(.conversations), "and conversations do too")
        try expect(need(.openAI, second: .openAI, actions: 1) == .needed(.secondShortcut), "the second shortcut comes before Actions")
        try expect(need(.openAI, dictation: .openAI) == .needed(.dictationModel(name: "dictation")), "an unnamed model still reads")
    }
}
