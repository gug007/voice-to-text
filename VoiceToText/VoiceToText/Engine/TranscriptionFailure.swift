import Foundation

/// A cloud transcription request that failed, carrying what the failure
/// card needs to tell the user something useful: whether the request got an
/// answer at all, and if so which status. Engines used to flatten this into
/// one sentence, so a bad key, a rate limit and a dropped Wi-Fi all got the
/// same Retry — useless for the first two.
///
/// Reads exactly as the `TranscriptionEngineError.transcriptionFailed` it
/// replaces ("Transcription failed: …"), so every place that shows an
/// engine error verbatim — History's regenerate note, the conversation
/// card — is unchanged.
///
/// Foundation-only and `nonisolated`, like `TranscriptionFailure`, so the
/// harness compiles both standalone.
nonisolated struct CloudTranscriptionError: LocalizedError, Sendable {
    enum Cause: Equatable, Sendable {
        /// The request got no answer: offline, DNS, a dropped connection.
        case transport(URLError.Code)
        /// The server answered with a non-2xx status. `apiCode` is the
        /// provider's machine-readable error code, when the body had one.
        case http(status: Int, retryAfter: TimeInterval?, apiCode: String?)
    }

    let cause: Cause
    /// Written to follow "Transcription failed: ".
    let reason: String

    var errorDescription: String? { "Transcription failed: \(reason)" }

    /// A non-2xx response. `Retry-After` is honoured in all three shapes a
    /// server may send it: OpenAI's `retry-after-ms`, then delta-seconds or
    /// an HTTP date. The body's code is read from the `{"error": {"code"}}`
    /// envelope OpenAI uses.
    static func http(
        _ response: HTTPURLResponse,
        body: Data,
        reason: String,
        now: Date = Date()
    ) -> CloudTranscriptionError {
        CloudTranscriptionError(
            cause: .http(
                status: response.statusCode,
                retryAfter: retryAfter(
                    milliseconds: response.value(forHTTPHeaderField: "retry-after-ms"),
                    header: response.value(forHTTPHeaderField: "Retry-After"),
                    now: now
                ),
                apiCode: apiCode(in: body)
            ),
            reason: reason
        )
    }

    /// The longest wait a server is taken at its word for. Anything past a day
    /// is a broken header, not advice — and `Double` happily parses "inf" and
    /// "1e30", which would trap the moment they were turned into an `Int`.
    static let maxRetryAfter: TimeInterval = 86_400

    static func retryAfter(milliseconds: String?, header: String?, now: Date) -> TimeInterval? {
        if let ms = milliseconds.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
           ms.isFinite, ms >= 0 {
            return min(ms / 1_000, maxRetryAfter)
        }
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else {
            return nil
        }
        if let seconds = Double(header) {
            return seconds.isFinite && seconds >= 0 ? min(seconds, maxRetryAfter) : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: header) else { return nil }
        return min(max(0, date.timeIntervalSince(now)), maxRetryAfter)
    }

    private static func apiCode(in body: Data) -> String? {
        struct Envelope: Decodable {
            struct ErrorBody: Decodable { let code: String? }
            let error: ErrorBody
        }
        return (try? JSONDecoder().decode(Envelope.self, from: body))?.error.code
    }
}

/// What kind of trouble a failed transcription ran into, as far as the user
/// can do anything about it — which is what decides what the failure card
/// says and offers.
nonisolated enum TranscriptionFailure: Equatable, Sendable {
    /// No network. Retry once connected, or use a model on this Mac.
    case offline
    /// The provider refused the API key (401, or a 403 that names the key).
    /// The card points at the key; Retry stays for after it's fixed.
    case unauthorized
    /// Too many requests. `retryAfter` is when the provider said to try
    /// again, if it said.
    case rateLimited(retryAfter: TimeInterval?)
    /// The provider's own failure (5xx). Usually passes.
    case server
    /// Anything else — the engine's own message says it best.
    case other

    static func classify(_ error: Error) -> TranscriptionFailure {
        if let cloud = error as? CloudTranscriptionError {
            return classify(cloud.cause)
        }
        if let url = error as? URLError {
            return classify(transport: url.code)
        }
        return .other
    }

    static func classify(_ cause: CloudTranscriptionError.Cause) -> TranscriptionFailure {
        switch cause {
        case .transport(let code):
            return classify(transport: code)
        case .http(let status, let retryAfter, let apiCode):
            switch status {
            case 401:
                return .unauthorized
            // A 403 is usually not about the key: OpenAI sends it for a model
            // the project can't use (`model_not_found`, which the engine
            // already explains) and for unsupported regions. Only one that
            // names the key is one.
            case 403:
                return apiCode.map(keyRelatedAPICodes.contains) == true ? .unauthorized : .other
            case 429:
                // OpenAI answers an exhausted balance with a 429 too, and no
                // amount of waiting fixes that — its own message (about
                // billing) is the useful one.
                return apiCode == "insufficient_quota" ? .other : .rateLimited(retryAfter: retryAfter)
            case 500...599:
                return .server
            default:
                return .other
            }
        }
    }

    /// OpenAI's error code for a key it doesn't accept.
    static let keyRelatedAPICodes: Set<String> = ["invalid_api_key"]

    /// Only the codes that mean this Mac has no usable network. A timeout or
    /// a refused connection can just as well be a slow or unwell server, and
    /// telling the user they're offline when they aren't is worse than the
    /// engine's own "Network error: …".
    static func classify(transport code: URLError.Code) -> TranscriptionFailure {
        switch code {
        case .notConnectedToInternet,
             .cannotFindHost,
             .dnsLookupFailed,
             .dataNotAllowed,
             .internationalRoamingOff:
            return .offline
        default:
            return .other
        }
    }

    /// The failure card's message. `provider` names the service ("OpenAI"),
    /// or nil for a local model; `fallback` is the engine's own message,
    /// which `.other` keeps.
    func message(provider: String?, fallback: String) -> String {
        let service = provider ?? "The transcription service"
        switch self {
        case .offline:
            return "You're offline. Retry once you're connected, or switch to a model on this Mac."
        case .unauthorized:
            return "\(service) didn't accept your API key."
        case .rateLimited(let retryAfter):
            guard let wait = retryAfter.map(Self.waitDescription) else {
                return "\(service) is rate-limiting requests. Wait a moment, then retry."
            }
            return "\(service) is rate-limiting requests. Retry in \(wait)."
        case .server:
            return "\(service) is having trouble right now. Retry in a moment."
        case .other:
            return fallback
        }
    }

    /// "20s" under a minute, whole minutes (rounded up) past it. Clamped like
    /// `CloudTranscriptionError.retryAfter`, so no value can trap the `Int`.
    static func waitDescription(_ seconds: TimeInterval) -> String {
        let limit = CloudTranscriptionError.maxRetryAfter
        let bounded = seconds.isFinite ? min(max(0, seconds), limit) : limit
        let whole = Int(bounded.rounded(.up))
        guard whole >= 60 else { return "\(max(1, whole))s" }
        return "\((whole + 59) / 60) min"
    }
}
