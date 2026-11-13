import Foundation

struct ModelDownloadFailureHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw ModelDownloadFailureHarnessFailure(description: message)
    }
}

/// The shapes the SDKs throw, rebuilt: WhisperKit's Hub wraps a status in an
/// internal enum and flattens some transport errors into a string; FluidAudio
/// nests an `NSError(domain: "HTTP")`; the engines wrap everything once more.
private enum HubLikeError: Error {
    case httpStatusCode(Int)
    case downloadError(String)
    case networkError(URLError)
}

private enum FluidLikeError: Error {
    case rateLimited(statusCode: Int, message: String)
    case downloadFailed(path: String, underlying: Error)
}

private enum EngineLikeError: Error {
    case modelLoadFailed(String, underlying: (any Error)?)
}

private typealias Failure = ModelDownloadFailure

@main
struct ModelDownloadFailureHarness {
    static func main() throws {
        try transportErrorsAreRead()
        try nestedSDKErrorsAreRead()
        try diskSpaceIsRead()
        try theNetworkPathSettlesAFlattenedError()
        try aCancelIsNotAFailure()
        try sentencesArePlain()
        try theFallbackIsOneSentence()
        print("Model download failure harness passed")
    }

    private static func transportErrorsAreRead() throws {
        try expect(Failure.cause(of: URLError(.notConnectedToInternet)) == .offline, "no internet reads as offline")
        try expect(Failure.cause(of: URLError(.networkConnectionLost)) == .offline, "a dropped connection reads as offline")
        try expect(Failure.cause(of: URLError(.timedOut)) == .timedOut, "a timeout reads as one")
        try expect(Failure.cause(of: URLError(.cannotFindHost)) == .server(status: nil), "an unknown host reads as unreachable")
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENETUNREACH))
        try expect(Failure.cause(of: posix) == .offline, "an unreachable network reads as offline")
    }

    private static func nestedSDKErrorsAreRead() throws {
        try expect(Failure.cause(of: HubLikeError.httpStatusCode(503)) == .server(status: 503), "a status inside an enum payload is found")
        try expect(
            Failure.cause(of: HubLikeError.networkError(URLError(.networkConnectionLost))) == .offline,
            "a URLError inside an enum payload is found"
        )
        try expect(
            Failure.cause(of: FluidLikeError.rateLimited(statusCode: 429, message: "slow down")) == .server(status: 429),
            "a labelled status inside a tuple payload is found"
        )
        let http = FluidLikeError.downloadFailed(path: "Encoder.mlmodelc", underlying: NSError(domain: "HTTP", code: 502))
        try expect(Failure.cause(of: http) == .server(status: 502), "an HTTP-domain NSError underneath is a status")
        let wrapped = EngineLikeError.modelLoadFailed("…", underlying: URLError(.timedOut))
        try expect(Failure.cause(of: wrapped) == .timedOut, "an optional underlying error is walked")
        let chained = NSError(domain: "Outer", code: 1, userInfo: [NSUnderlyingErrorKey: URLError(.notConnectedToInternet)])
        try expect(Failure.cause(of: chained) == .offline, "the NSUnderlyingErrorKey chain is walked")
        try expect(Failure.cause(of: HubLikeError.httpStatusCode(7)) != .server(status: 7), "a number that isn't a status is ignored")
    }

    private static func diskSpaceIsRead() throws {
        let full = Failure.cause(of: CocoaError(.fileWriteOutOfSpace), neededBytes: 1_640_000_000, freeBytes: 420_000_000)
        try expect(full == .diskFull(neededBytes: 1_640_000_000, freeBytes: 420_000_000), "Cocoa's out-of-space reads as a full disk")
        let posix = NSError(domain: "Outer", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])
        try expect(Failure.cause(of: posix) == .diskFull(neededBytes: nil, freeBytes: nil), "ENOSPC underneath reads as a full disk")
        try expect(
            Failure.cause(of: CocoaError(.fileWriteOutOfSpace), isOffline: true) == .diskFull(neededBytes: nil, freeBytes: nil),
            "a full disk is the reason even offline"
        )
        let vague = NSError(domain: "com.apple.CoreML", code: 0, userInfo: [NSLocalizedDescriptionKey: "Compile failed."])
        try expect(
            Failure.cause(of: vague, neededBytes: 500, freeBytes: 100) == .diskFull(neededBytes: 500, freeBytes: 100),
            "an unexplained failure with too little room left is put down to the disk"
        )
        try expect(
            Failure.cause(of: vague, neededBytes: 500, freeBytes: 1_000) == .other("Compile failed."),
            "with room to spare it stays unexplained"
        )
    }

    private static func theNetworkPathSettlesAFlattenedError() throws {
        let flattened = HubLikeError.downloadError("The Internet connection appears to be offline.")
        try expect(Failure.cause(of: flattened, isOffline: true) == .offline, "no network path reads as offline")
        if case .other = Failure.cause(of: flattened, isOffline: false) {} else {
            throw ModelDownloadFailureHarnessFailure(description: "a string alone is never parsed for a reason")
        }
    }

    private static func aCancelIsNotAFailure() throws {
        try expect(Failure.cause(of: CancellationError()) == .cancelled, "a task cancel reads as cancelled")
        try expect(Failure.cause(of: URLError(.cancelled)) == .cancelled, "a URL cancel reads as cancelled")
        try expect(
            Failure.cause(of: EngineLikeError.modelLoadFailed("…", underlying: CancellationError()), isOffline: true) == .cancelled,
            "a wrapped cancel wins over everything"
        )
        try expect(Failure.sentence(for: .cancelled, formatBytes: format) == nil, "a cancel has no failure sentence")
    }

    private static func format(_ bytes: Int64) -> String { "\(bytes / 1_000_000) MB" }

    private static func sentencesArePlain() throws {
        try expect(Failure.sentence(for: .offline, formatBytes: format) == "You appear to be offline.", "offline")
        try expect(Failure.sentence(for: .timedOut, formatBytes: format) == "The connection timed out.", "timed out")
        try expect(
            Failure.sentence(for: .diskFull(neededBytes: 1_640_000_000, freeBytes: 420_000_000), formatBytes: format)
                == "Not enough disk space: needs 1640 MB, 420 MB free.",
            "a full disk says what's needed and what's free"
        )
        try expect(
            Failure.sentence(for: .diskFull(neededBytes: nil, freeBytes: 420), formatBytes: format) == "Not enough disk space on this Mac.",
            "without both figures it says neither"
        )
        try expect(Failure.sentence(for: .server(status: nil), formatBytes: format) == "Couldn't reach the download server.", "unreachable")
        try expect(Failure.sentence(for: .server(status: 503), formatBytes: format)?.contains("unavailable (HTTP 503)") == true, "5xx is unavailable")
        try expect(Failure.sentence(for: .server(status: 429), formatBytes: format)?.contains("busy (HTTP 429)") == true, "429 is busy")
        try expect(Failure.sentence(for: .server(status: 403), formatBytes: format)?.contains("refused the request (HTTP 403)") == true, "4xx is refused")
        try expect(Failure.sentence(for: .server(status: 404), formatBytes: format)?.contains("HTTP 404") == true, "404 says not found")
        try expect(Failure.sentence(for: .stalled, formatBytes: format) == "The download stopped responding.", "stalled")
        for cause: Failure.Cause in [.offline, .timedOut, .server(status: 500), .stalled, .diskFull(neededBytes: nil, freeBytes: nil)] {
            let sentence = Failure.sentence(for: cause, formatBytes: format) ?? ""
            try expect(!sentence.contains("!") && !sentence.contains("\n"), "\(cause) is one calm line")
        }
    }

    private static func theFallbackIsOneSentence() throws {
        let other = Failure.Cause.other("The operation couldn’t be completed. (ArgmaxCore.Hub.HubClientError error 5.)")
        try expect(
            Failure.sentence(for: other, formatBytes: format) == "The operation couldn’t be completed.",
            "the system's description is cut to its first sentence"
        )
        try expect(Failure.firstSentence(of: "Model v1.2 failed to compile") == "Model v1.2 failed to compile.", "a decimal isn't a sentence end, and a full stop is added")
        try expect(Failure.firstSentence(of: "First line\nSecond line.") == "First line.", "only the first line")
        try expect(Failure.firstSentence(of: "   ") == nil, "blank has no sentence")
        try expect(Failure.sentence(for: .other(""), formatBytes: format) == "The download failed.", "blank falls back to a generic line")
        let long = String(repeating: "word ", count: 60)
        let cut = Failure.firstSentence(of: long) ?? ""
        try expect(cut.count <= 140 && cut.hasSuffix("…"), "a long description is cut short with an ellipsis")
    }
}
