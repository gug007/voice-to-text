import Foundation

struct DictationRescueHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw DictationRescueHarnessFailure(description: message)
    }
}

/// The rescue past the failure card: what a failed Resume take's banner
/// keeps of the card's buttons, and how the transcribing card names the wait
/// for a model on this Mac.
@main
struct DictationRescueHarness {
    typealias Rescue = DictationRescue
    typealias Policy = DictationTakePolicy

    static func main() throws {
        try outOfCreditTheBannerLeadsWithTheMacAndDropsRetry()
        try aRepeatRefusalKeepsTheLastingSwitchOnTheCard()
        try outOfCreditWithNothingOnThisMacKeepsRetry()
        try offlineTheBannerKeepsRetryForOnceConnected()
        try everyOtherCardFitsTheBannerAsItIs()
        try aDownloadIsNeverMistakenForTheCompileTail()
        try aModelOnDiskCanOnlyBeLoading()
        try onlyAMovingDownloadShowsAFraction()
        print("Dictation rescue harness passed")
    }

    private static let ready = Policy.LocalFallback.ready(id: "parakeet-tdt-v3", coversLanguages: true)
    private static let download = Policy.LocalFallback.download(id: "parakeet-tdt-v3", sizeMB: 470)

    private static func banner(
        _ failure: TranscriptionFailure,
        _ local: Policy.LocalFallback?,
        repeat isRepeat: Bool = false
    ) -> Rescue.ResumeBanner {
        Rescue.resumeBanner(
            failure: failure,
            actions: Policy.failureCard(failure: failure, local: { local }, isRepeatRefusal: isRepeat)
        )
    }

    private static func outOfCreditTheBannerLeadsWithTheMacAndDropsRetry() throws {
        let onMac = banner(.quotaExhausted, ready)
        try expect(onMac.action == .transcribeOnMac(id: "parakeet-tdt-v3"), "Transcribe on Mac: \(onMac)")
        try expect(onMac.retry == nil, "no Retry the empty balance would only refuse: \(onMac)")

        let fetch = banner(.quotaExhausted, download)
        try expect(
            fetch.action == .downloadAndTranscribe(id: "parakeet-tdt-v3", sizeMB: 470),
            "Download & Transcribe: \(fetch)"
        )
        try expect(fetch.retry == nil, "and no Retry beside it: \(fetch)")
    }

    private static func aRepeatRefusalKeepsTheLastingSwitchOnTheCard() throws {
        let again = banner(.quotaExhausted, ready, repeat: true)
        try expect(
            again == .init(retry: nil, action: .transcribeOnMac(id: "parakeet-tdt-v3")),
            "the banner offers the take's model, not Use for Dictation: \(again)"
        )
    }

    private static func outOfCreditWithNothingOnThisMacKeepsRetry() throws {
        for isRepeat in [false, true] {
            let none = banner(.quotaExhausted, nil, repeat: isRepeat)
            try expect(
                none == .init(retry: .retry, action: .chooseModel),
                "with no model to offer, Retry stays beside Choose Model (repeat \(isRepeat)): \(none)"
            )
        }
    }

    private static func offlineTheBannerKeepsRetryForOnceConnected() throws {
        let onMac = banner(.offline, ready)
        try expect(
            onMac == .init(retry: .retryCloud, action: .transcribeOnMac(id: "parakeet-tdt-v3")),
            "offline keeps Retry <provider> beside the model on this Mac: \(onMac)"
        )
        let none = banner(.offline, nil)
        try expect(none == .init(retry: .retry, action: nil), "offline with nothing installed: Retry alone: \(none)")
    }

    private static func everyOtherCardFitsTheBannerAsItIs() throws {
        try expect(
            banner(.unauthorized, nil) == .init(retry: .retry, action: .checkAPIKey),
            "a refused key keeps Check API Key beside Retry"
        )
        for failure in [TranscriptionFailure.rateLimited(retryAfter: 20), .server, .other] {
            try expect(banner(failure, ready) == .init(retry: .retry, action: nil), "\(failure): Retry alone")
        }
    }

    private static func aDownloadIsNeverMistakenForTheCompileTail() throws {
        for message in ["Downloading 3/12 files", "downloading model", "Starting…", "Listing files…", "Connecting to HuggingFace…"] {
            try expect(
                Rescue.modelWait(message: message, wasOnDisk: false) == .downloading,
                "\"\(message)\" for a model not on disk is the download"
            )
        }
        try expect(
            Rescue.modelWait(message: "Downloading 3/12 files", wasOnDisk: true) == .downloading,
            "a folder that turned out incomplete downloads again, and says so"
        )
        for message in ["Compiling AudioEncoder…", "Loading model into memory…"] {
            try expect(
                Rescue.modelWait(message: message, wasOnDisk: false) == .loading,
                "\"\(message)\" is the load after the download"
            )
        }
    }

    private static func aModelOnDiskCanOnlyBeLoading() throws {
        for message in ["Starting…", "Listing files…", "Compiling AudioEncoder…", ""] {
            try expect(
                Rescue.modelWait(message: message, wasOnDisk: true) == .loading,
                "\"\(message)\" for a model on disk is a load, not a download"
            )
        }
    }

    private static func onlyAMovingDownloadShowsAFraction() throws {
        try expect(Rescue.shownFraction(0.42, during: .downloading) == 0.42, "a download shows its progress")
        try expect(Rescue.shownFraction(0, during: .downloading) == nil, "a download that hasn't moved is indeterminate")
        try expect(Rescue.shownFraction(.nan, during: .downloading) == nil, "and so is one with no number")
        try expect(Rescue.shownFraction(1.3, during: .downloading) == 1, "never past the end")
        try expect(Rescue.shownFraction(0.95, during: .loading) == nil, "a load is indeterminate, whatever it reports")
    }
}
