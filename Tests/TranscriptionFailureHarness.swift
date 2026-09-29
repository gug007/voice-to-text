import Foundation

struct TranscriptionFailureHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TranscriptionFailureHarnessFailure(description: message)
    }
}

private func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw TranscriptionFailureHarnessFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
private let now = Date(timeIntervalSince1970: 1_790_000_000)

private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
}

private func openAIBody(code: String?) -> Data {
    let codeField = code.map { "\"\($0)\"" } ?? "null"
    return Data("{\"error\": {\"message\": \"nope\", \"type\": \"x\", \"code\": \(codeField)}}".utf8)
}

private func httpFailure(
    _ status: Int,
    headers: [String: String] = [:],
    code: String? = nil
) -> TranscriptionFailure {
    TranscriptionFailure.classify(
        CloudTranscriptionError.http(response(status, headers: headers), body: openAIBody(code: code), reason: "OpenAI: nope", now: now)
    )
}

private struct EngineError: LocalizedError {
    var errorDescription: String? { "Model load failed: out of memory" }
}

@main
struct TranscriptionFailureHarness {
    static func main() throws {
        try refusedKeysAreUnauthorized()
        try otherForbiddensKeepTheEngineMessage()
        try rateLimitsCarryRetryAfter()
        try absurdRetryAftersAreBounded()
        try exhaustedQuotaIsNotARateLimit()
        try serverErrorsAreServer()
        try otherStatusesKeepTheEngineMessage()
        try onlyNoNetworkCodesAreOffline()
        try foreignErrorsAreOther()
        try messagesSayWhatHelps()
        try waitsReadNaturally()
        try describesLikeTheErrorItReplaced()
        print("Transcription failure harness passed")
    }

    private static func refusedKeysAreUnauthorized() throws {
        try expect(httpFailure(401), .unauthorized, "401 is a refused key")
        try expect(httpFailure(401, code: "invalid_api_key"), .unauthorized, "with or without a code")
        try expect(httpFailure(403, code: "invalid_api_key"), .unauthorized, "a 403 that names the key")
    }

    /// OpenAI's 403s are mostly not about the key, and the engine's own
    /// message for them is the useful one.
    private static func otherForbiddensKeepTheEngineMessage() throws {
        try expect(httpFailure(403, code: "model_not_found"), .other, "a model the project can't use")
        try expect(httpFailure(403, code: "unsupported_country_region_territory"), .other, "a region block")
        try expect(httpFailure(403), .other, "an unexplained 403")
    }

    private static func rateLimitsCarryRetryAfter() throws {
        try expect(httpFailure(429, headers: ["Retry-After": "20"]), .rateLimited(retryAfter: 20), "delta-seconds")
        try expect(httpFailure(429, headers: ["retry-after-ms": "1500"]), .rateLimited(retryAfter: 1.5), "OpenAI's milliseconds")
        try expect(
            httpFailure(429, headers: ["retry-after-ms": "250", "Retry-After": "9"]),
            .rateLimited(retryAfter: 0.25),
            "milliseconds win: they are the precise one"
        )
        let date = "Wed, 28 Jul 2027 07:07:10 GMT"  // 30 s after the `now` below
        try expect(
            TranscriptionFailure.classify(.http(
                status: 429,
                retryAfter: CloudTranscriptionError.retryAfter(
                    milliseconds: nil,
                    header: date,
                    now: Date(timeIntervalSince1970: 1_816_758_400)
                ),
                apiCode: nil
            )),
            .rateLimited(retryAfter: 30),
            "an HTTP date is measured from now"
        )
        try expect(httpFailure(429), .rateLimited(retryAfter: nil), "no header, no promise")
        try expect(httpFailure(429, headers: ["Retry-After": "soon"]), .rateLimited(retryAfter: nil), "garbage is ignored")
        try expect(httpFailure(429, headers: ["Retry-After": "-5"]), .rateLimited(retryAfter: nil), "a negative wait is ignored")
    }

    /// `Double` parses these, and an unchecked one traps when the card turns
    /// it into whole seconds.
    private static func absurdRetryAftersAreBounded() throws {
        let day = CloudTranscriptionError.maxRetryAfter
        try expect(httpFailure(429, headers: ["Retry-After": "inf"]), .rateLimited(retryAfter: nil), "infinity is no answer")
        try expect(httpFailure(429, headers: ["Retry-After": "nan"]), .rateLimited(retryAfter: nil), "nor is NaN")
        try expect(httpFailure(429, headers: ["Retry-After": "1e30"]), .rateLimited(retryAfter: day), "a huge wait is clamped to a day")
        try expect(httpFailure(429, headers: ["retry-after-ms": "inf", "Retry-After": "7"]), .rateLimited(retryAfter: 7), "a non-finite ms header falls back to seconds")
        try expect(httpFailure(429, headers: ["retry-after-ms": "1e40"]), .rateLimited(retryAfter: day), "huge milliseconds are clamped")
        try expect(
            CloudTranscriptionError.retryAfter(milliseconds: nil, header: "Fri, 31 Dec 9999 23:59:59 GMT", now: now) == day,
            true,
            "a far-future date is clamped too"
        )
        try expect(TranscriptionFailure.waitDescription(.infinity), "1440 min", "the wait text never traps")
        try expect(TranscriptionFailure.waitDescription(1e30), "1440 min", "on any value")
        try expect(TranscriptionFailure.waitDescription(-3), "1s", "or a negative one")
        _ = TranscriptionFailure.waitDescription(.nan)
    }

    private static func exhaustedQuotaIsNotARateLimit() throws {
        try expect(
            httpFailure(429, headers: ["Retry-After": "20"], code: "insufficient_quota"),
            .other,
            "an empty balance doesn't refill by waiting"
        )
        try expect(httpFailure(429, code: "rate_limit_exceeded"), .rateLimited(retryAfter: nil), "a real rate limit")
    }

    private static func serverErrorsAreServer() throws {
        for status in [500, 502, 503, 504] {
            try expect(httpFailure(status), .server, "\(status) is the provider's trouble")
        }
    }

    private static func otherStatusesKeepTheEngineMessage() throws {
        try expect(httpFailure(400), .other, "a bad request")
        try expect(httpFailure(404), .other, "an unknown model has its own message")
        try expect(httpFailure(413), .other, "too large")
    }

    private static func onlyNoNetworkCodesAreOffline() throws {
        let transport = { (code: URLError.Code) in
            TranscriptionFailure.classify(CloudTranscriptionError(cause: .transport(code), reason: "Network error: x"))
        }
        for code: URLError.Code in [.notConnectedToInternet, .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff] {
            try expect(transport(code), .offline, "\(code.rawValue) means no network")
        }
        for code: URLError.Code in [.timedOut, .cannotConnectToHost, .networkConnectionLost, .secureConnectionFailed, .cancelled] {
            try expect(transport(code), .other, "\(code.rawValue) can be the server's fault")
        }
        try expect(
            TranscriptionFailure.classify(URLError(.notConnectedToInternet)),
            .offline,
            "a bare URLError is read the same way"
        )
    }

    private static func foreignErrorsAreOther() throws {
        try expect(TranscriptionFailure.classify(EngineError()), .other, "an engine's own error")
        try expect(TranscriptionFailure.classify(CancellationError()), .other, "a cancellation")
    }

    private static func messagesSayWhatHelps() throws {
        let fallback = "Transcription failed: OpenAI: nope"
        try expect(
            TranscriptionFailure.unauthorized.message(provider: "OpenAI", fallback: fallback),
            "OpenAI didn't accept your API key.",
            "names the provider"
        )
        try expect(
            TranscriptionFailure.rateLimited(retryAfter: 20).message(provider: "OpenAI", fallback: fallback),
            "OpenAI is rate-limiting requests. Retry in 20s.",
            "says how long to wait"
        )
        try expect(
            TranscriptionFailure.rateLimited(retryAfter: nil).message(provider: "OpenAI", fallback: fallback),
            "OpenAI is rate-limiting requests. Wait a moment, then retry.",
            "or that it doesn't know"
        )
        try expect(
            TranscriptionFailure.offline.message(provider: "OpenAI", fallback: fallback),
            "You're offline. Retry once you're connected, or switch to a model on this Mac.",
            "suggests a local model"
        )
        try expect(
            TranscriptionFailure.server.message(provider: nil, fallback: fallback),
            "The transcription service is having trouble right now. Retry in a moment.",
            "no provider name to give"
        )
        try expect(TranscriptionFailure.other.message(provider: "OpenAI", fallback: fallback), fallback, "other keeps the engine's message")
    }

    private static func waitsReadNaturally() throws {
        try expect(TranscriptionFailure.waitDescription(0.2), "1s", "never zero")
        try expect(TranscriptionFailure.waitDescription(1.5), "2s", "rounded up, so retrying on time works")
        try expect(TranscriptionFailure.waitDescription(59), "59s", "seconds under a minute")
        try expect(TranscriptionFailure.waitDescription(59.5), "1 min", "a minute")
        try expect(TranscriptionFailure.waitDescription(61), "2 min", "minutes rounded up")
    }

    private static func describesLikeTheErrorItReplaced() throws {
        let error = CloudTranscriptionError.http(response(401), body: openAIBody(code: "invalid_api_key"), reason: "OpenAI: Incorrect API key provided.")
        try expect(
            error.localizedDescription,
            "Transcription failed: OpenAI: Incorrect API key provided.",
            "the same sentence the engine always threw"
        )
        try expect(error.cause, .http(status: 401, retryAfter: nil, apiCode: "invalid_api_key"), "status and code are kept")
    }
}
