import AppKit
import Foundation

struct FailureCardCopyHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw FailureCardCopyHarnessFailure(description: message)
    }
}

/// Holds the rescue's copy to the words the spec chose and to the room the
/// 600pt failure card gives it — measured with the card's own fonts, for the
/// longest names it can show: "Whisper Large v3 Turbo" and "ElevenLabs".
@main
struct FailureCardCopyHarness {
    typealias Copy = FailureCardCopy
    typealias Policy = DictationTakePolicy

    static func main() throws {
        try theCardSaysWhatTheButtonsDo()
        try aRepeatRefusalMovesOnFromTopUp()
        try offlineCopyNeverPromisesADownload()
        try otherFailuresKeepTheirOwnMessage()
        try theDetailLineSaysWhatTheModelCosts()
        try aLongNameDropsTheFlourishNotTheFacts()
        try aModelThatDoesntKnowTheLanguagesSaysSo()
        try buttonsAreNamedForWhatTheyDo()
        try theResumeBannerOnlySaysWhy()
        try downloadCopy()
        try historyAndSettingsCopy()
        try everyCardFitsTheCard()
        print("Failure card copy harness passed")
    }

    private static let parakeet = "Parakeet TDT v3"
    private static let turbo = "Whisper Large v3 Turbo"

    private static func card(
        _ failure: TranscriptionFailure,
        _ local: Policy.LocalFallback?,
        provider: String? = "OpenAI",
        localName: String? = nil,
        localLanguages: String? = "25 European languages",
        seconds: TimeInterval = 42,
        saved: Bool = true,
        repeat isRepeat: Bool = false,
        engineMessage: String = "Transcription failed: something odd."
    ) -> Copy.Card {
        Copy.card(
            failure: failure,
            actions: Policy.failureCard(failure: failure, local: { local }, isRepeatRefusal: isRepeat),
            provider: provider,
            local: local,
            localName: localName ?? (local?.modelID == "whisper-large-v3-turbo" ? turbo : parakeet),
            localLanguages: localLanguages,
            capturedSeconds: seconds,
            savedToHistory: saved,
            isRepeatRefusal: isRepeat,
            engineMessage: engineMessage
        )
    }

    private static let ready = Policy.LocalFallback.ready(id: "parakeet-tdt-v3", coversLanguages: true)
    private static let download = Policy.LocalFallback.download(id: "parakeet-tdt-v3", sizeMB: 470)

    private static func theCardSaysWhatTheButtonsDo() throws {
        let first = card(.quotaExhausted, ready)
        try expect(
            first.banner == "OpenAI says your account is out of credit. Transcribe this take on your Mac, or top up and retry.",
            "first refusal banner: \(first.banner)"
        )
        try expect(first.primary == .init(title: "Transcribe on Mac", icon: "laptopcomputer", hint: "↩"), "primary: \(first.primary)")
        try expect(first.secondary == .init(title: "Retry OpenAI", icon: "arrow.clockwise", hint: nil), "secondary: \(String(describing: first.secondary))")

        let fetch = card(.quotaExhausted, download)
        try expect(fetch.banner == first.banner, "a download needed says the same")
        try expect(fetch.primary == .init(title: "Download & Transcribe", icon: "arrow.down.circle", hint: "↩"), "primary: \(fetch.primary)")

        let none = card(.quotaExhausted, nil, repeat: true)
        try expect(none.banner == first.banner, "with nothing on this Mac, a repeat refusal doesn't point at a model that isn't there")
        try expect(none.primary.title == "Retry" && none.primary.hint == "↩", "Retry leads")
        try expect(none.secondary?.title == "Choose Model", "beside Choose Model")
    }

    private static func aRepeatRefusalMovesOnFromTopUp() throws {
        let again = card(.quotaExhausted, ready, provider: "ElevenLabs", repeat: true)
        try expect(
            again.banner == "ElevenLabs is still out of credit. Transcribe on your Mac, or use it for dictation until you top up.",
            "repeat banner: \(again.banner)"
        )
        try expect(again.secondary?.title == "Use for Dictation", "the lasting switch is offered")
    }

    private static func offlineCopyNeverPromisesADownload() throws {
        let onMac = card(.offline, ready)
        try expect(
            onMac.banner == "You're offline. Transcribe this take on your Mac, or retry once you're connected.",
            "offline banner: \(onMac.banner)"
        )
        try expect(onMac.secondary?.title == "Retry OpenAI", "offline keeps Retry <provider>")

        let none = card(.offline, nil)
        try expect(none.banner == "You're offline. Retry once you're connected.", "offline, nothing installed: \(none.banner)")
        try expect(none.detail == "42.0s saved to History.", "detail: \(String(describing: none.detail))")
        try expect(none.primary.title == "Retry" && none.secondary == nil, "Close and Retry only")
    }

    private static func otherFailuresKeepTheirOwnMessage() throws {
        let key = card(.unauthorized, nil)
        try expect(key.banner == "OpenAI didn't accept your API key.", "unauthorized keeps its message")
        try expect(key.detail == nil, "and the card's own captured line")
        try expect(key.secondary?.title == "Check API Key", "with Check API Key")
        let other = card(.other, nil)
        try expect(other.banner == "Transcription failed: something odd.", "other keeps the engine's words")
    }

    private static func theDetailLineSaysWhatTheModelCosts() throws {
        try expect(
            card(.quotaExhausted, ready, seconds: 102).detail
                == "1:42 saved to History · Parakeet TDT v3 runs on this Mac — free and private.",
            "ready detail: \(String(describing: card(.quotaExhausted, ready, seconds: 102).detail))"
        )
        try expect(
            card(.quotaExhausted, download, seconds: 102).detail
                == "1:42 saved to History · Parakeet TDT v3 is a one-time 470 MB download.",
            "download detail"
        )
        try expect(
            card(.quotaExhausted, ready, saved: false).detail
                == "42.0s captured, not saved · Parakeet TDT v3 runs on this Mac — free and private.",
            "a take History couldn't keep says so: \(String(describing: card(.quotaExhausted, ready, saved: false).detail))"
        )
        try expect(Copy.sizeText(megabytes: 632) == "632 MB", "sizes under a gigabyte in MB")
        try expect(Copy.sizeText(megabytes: 1_550) == "1.6 GB", "and over it in GB")
    }

    private static func aLongNameDropsTheFlourishNotTheFacts() throws {
        let turboReady = Policy.LocalFallback.ready(id: "whisper-large-v3-turbo", coversLanguages: true)
        let saved = card(.quotaExhausted, turboReady, seconds: 3_723).detail
        try expect(
            saved == "1:02:03 saved to History · Whisper Large v3 Turbo runs on this Mac — free and private.",
            "the longest name still fits it beside an hour-long saved take: \(String(describing: saved))"
        )
        let unsaved = card(.quotaExhausted, turboReady, seconds: 3_723, saved: false).detail
        try expect(
            unsaved == "1:02:03 captured, not saved · Whisper Large v3 Turbo runs on this Mac.",
            "past the line it drops \"— free and private\": \(String(describing: unsaved))"
        )
    }

    private static func aModelThatDoesntKnowTheLanguagesSaysSo() throws {
        let partial = card(.offline, .ready(id: "parakeet-tdt-v3", coversLanguages: false))
        try expect(
            partial.detail == "42.0s saved to History · Parakeet TDT v3 covers 25 European languages only.",
            "uncovered detail: \(String(describing: partial.detail))"
        )
    }

    private static func buttonsAreNamedForWhatTheyDo() throws {
        let expected: [(Policy.CardAction, String)] = [
            (.retry, "Retry"),
            (.retryCloud, "Retry ElevenLabs"),
            (.transcribeOnMac(id: "x"), "Transcribe on Mac"),
            (.downloadAndTranscribe(id: "x", sizeMB: 1), "Download & Transcribe"),
            (.useForDictation(id: "x"), "Use for Dictation"),
            (.chooseModel, "Choose Model"),
            (.checkAPIKey, "Check API Key"),
        ]
        for (action, title) in expected {
            try expect(Copy.title(of: action, provider: "ElevenLabs") == title, "\(action) is \(title)")
        }
        try expect(Copy.title(of: .retryCloud, provider: nil) == "Retry", "no provider, plain Retry")
    }

    private static func theResumeBannerOnlySaysWhy() throws {
        let actions = Policy.failureCard(failure: .quotaExhausted, local: { ready }, isRepeatRefusal: false)
        try expect(
            Copy.reviewBanner(failure: .quotaExhausted, primary: actions.primary, provider: "OpenAI", engineMessage: "")
                == "OpenAI is out of credit.",
            "the Resume banner is short; its button says what to do"
        )
    }

    private static func downloadCopy() throws {
        try expect(Copy.percent(nil) == nil && Copy.percent(0) == nil, "no fraction is indeterminate, not 0%")
        try expect(Copy.percent(0.425) == "42%", "fractions round down")
        try expect(Copy.percent(1.2) == "100%", "and never pass 100%")
        try expect(Copy.downloadProgress(modelName: parakeet, fraction: 0.42) == "Parakeet TDT v3 · 42%", "progress")
        try expect(Copy.downloadProgress(modelName: parakeet, fraction: 0) == "Parakeet TDT v3", "name alone at zero")
        try expect(Copy.preparePhaseTitle(isLoading: false) == "Downloading", "phase")
        try expect(Copy.preparePhaseTitle(isLoading: true) == "Loading", "load phase")
        try expect(
            Copy.downloadFailed(modelName: parakeet, reason: nil)
                == "Couldn't download Parakeet TDT v3. Check your connection and try again.",
            "download failure"
        )
        try expect(
            Copy.downloadFailed(modelName: parakeet, reason: "Preparation stalled. Check your connection and try again.")
                == "Couldn't download Parakeet TDT v3. Preparation stalled. Check your connection and try again.",
            "with the registry's reason"
        )
        try expect(
            Copy.downloadFailed(modelName: parakeet, reason: "The disk is full")
                == "Couldn't download Parakeet TDT v3. The disk is full.",
            "a reason without a full stop gets one"
        )
        try expect(
            Copy.loadFailed(modelName: parakeet, reason: nil)
                == "Couldn't load Parakeet TDT v3. Try again, or re-download it in Models.",
            "a load failure doesn't blame the connection"
        )
        try expect(
            Copy.loadFailed(modelName: parakeet, reason: "Failed to load model: out of memory")
                == "Couldn't load Parakeet TDT v3. Failed to load model: out of memory.",
            "with the registry's reason"
        )
    }

    private static func historyAndSettingsCopy() throws {
        try expect(Copy.historyLocalTitle(ready, modelName: parakeet) == "Transcribe with Parakeet TDT v3", "history ready")
        try expect(
            Copy.historyLocalTitle(download, modelName: parakeet) == "Download & transcribe with Parakeet TDT v3 (470 MB)",
            "history download"
        )
        try expect(Copy.historyRetryTitle(cloudModelName: "GPT Transcribe") == "Retry with GPT Transcribe", "history retry")
        try expect(
            Copy.historyDownloading(modelName: parakeet, fraction: 0.42) == "Downloading Parakeet TDT v3 · 42%",
            "history downloading"
        )
        try expect(
            Copy.switchedBanner(cloudModelName: "GPT Transcribe", provider: "OpenAI")
                == "Switched from GPT Transcribe when OpenAI ran out of credit.",
            "models banner"
        )
    }

    // MARK: - Room on the card

    /// 600pt card, 12pt inset each side.
    private static let contentWidth: CGFloat = 600 - 2 * 12
    /// Inside the banner: its 12pt padding each side, the 11pt warning glyph,
    /// and the 8pt gaps either side of the text with the spacer's 8pt minimum.
    private static let bannerTextWidth: CGFloat = contentWidth - 2 * 12 - 12 - 3 * 8

    private static let bannerFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let detailFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private static let buttonFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let hintFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    private static func width(_ text: String, _ font: NSFont, tracking: CGFloat = 0) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: tracking]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    /// Lines `text` wraps to at `limit`, breaking between words as Text does.
    private static func lineCount(_ text: String, font: NSFont, tracking: CGFloat, limit: CGFloat) -> Int {
        var lines = 1
        var current = ""
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if width(candidate, font, tracking: tracking) <= limit {
                current = candidate
            } else {
                lines += 1
                current = String(word)
            }
        }
        return lines
    }

    private static func buttonWidth(_ button: Copy.Button) -> CGFloat {
        var width = 2 * 12 + Self.width(button.title, buttonFont)
        if !button.icon.isEmpty { width += 16 + 8 }
        if let hint = button.hint { width += 8 + Self.width(hint, hintFont, tracking: 0.2) }
        return width
    }

    private static func everyCardFitsTheCard() throws {
        let fallbacks: [Policy.LocalFallback?] = [
            .ready(id: "whisper-large-v3-turbo", coversLanguages: true),
            .ready(id: "parakeet-tdt-v3", coversLanguages: false),
            .download(id: "whisper-large-v3-turbo", sizeMB: 632),
            .download(id: "whisper-large-v3-turbo", sizeMB: 1_550),
            nil,
        ]
        let closeWidth = buttonWidth(.init(title: "Close", icon: "", hint: "esc"))
        for failure in [TranscriptionFailure.quotaExhausted, .offline] {
            for local in fallbacks {
                for isRepeat in [false, true] {
                    for saved in [false, true] {
                        for seconds in [8.4, 3_723.0] {
                            let copy = card(
                                failure,
                                local,
                                provider: "ElevenLabs",
                                localName: turbo,
                                localLanguages: "25 European languages",
                                seconds: seconds,
                                saved: saved,
                                repeat: isRepeat
                            )
                            let context = "\(failure), \(String(describing: local)), repeat \(isRepeat), saved \(saved), \(seconds)s"
                            try expect(
                                copy.banner.count <= Copy.bannerCharacterBudget,
                                "banner over its character budget (\(context)): \(copy.banner)"
                            )
                            let lines = lineCount(copy.banner, font: bannerFont, tracking: 0.06, limit: bannerTextWidth)
                            try expect(lines <= 2, "banner wraps to \(lines) lines (\(context)): \(copy.banner)")
                            if let detail = copy.detail {
                                try expect(
                                    detail.count <= Copy.detailCharacterBudget,
                                    "detail over its character budget (\(context)): \(detail)"
                                )
                                // 16pt short of the line: SwiftUI's own layout
                                // rounds differently from AppKit's measuring.
                                let measured = width(detail, detailFont)
                                try expect(
                                    measured <= contentWidth - 16,
                                    "detail is \(measured)pt of \(contentWidth) (\(context)): \(detail)"
                                )
                            }
                            let row = [copy.secondary.map(buttonWidth), closeWidth, buttonWidth(copy.primary)]
                                .compactMap { $0 }
                            let rowWidth = row.reduce(8, +) + CGFloat(row.count) * 8
                            try expect(
                                rowWidth <= contentWidth,
                                "control row is \(rowWidth)pt of \(contentWidth) (\(context))"
                            )
                        }
                    }
                }
            }
        }
    }
}
