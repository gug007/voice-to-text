import Foundation

/// The wire format of the local app API (`ExternalAPIServer`): one JSON object
/// per line, UTF-8, over a Unix socket. Requests carry an `id` the response
/// echoes; events carry an `event` name and no `id`. Pure Foundation, so the
/// harness compiles it on its own. INTEGRATION.md is the contract clients
/// build against — change the two together.
nonisolated enum ExternalAPI {
    /// Bumped only for a change an existing client would misread. Also
    /// published in Info.plist (`VoiceToTextAPIVersion`) so a client can tell
    /// an installed copy speaks the API without launching it.
    static let version = 1

    /// A line this long is a broken or hostile client, not a request.
    static let maxLineBytes = 64 * 1024

    enum Method: String, Sendable {
        case status
        case start
        case stop
        case cancel
    }

    enum ErrorCode: String, Sendable {
        case invalidRequest = "invalid_request"
        case unknownMethod = "unknown_method"
        /// The hotkey dictation, a conversation, or another client's session
        /// holds the microphone.
        case busy
        case notRecording = "not_recording"
        case microphoneDenied = "microphone_denied"
        case noModel = "no_model"
        case apiKeyMissing = "api_key_missing"
        case modelUnavailable = "model_unavailable"
        case recorderFailed = "recorder_failed"
        case tooShort = "too_short"
        case noSpeech = "no_speech"
        case transcriptionFailed = "transcription_failed"
        case cancelled
    }

    /// The request's `id`, echoed back verbatim: clients number them, or name
    /// them, and either must round-trip unchanged.
    enum RequestID: Equatable, Sendable {
        case number(Int)
        case string(String)

        init?(json: Any?) {
            switch json {
            case let value as String:
                self = .string(value)
            case let value as NSNumber where CFGetTypeID(value) != CFBooleanGetTypeID():
                guard let exact = Int(exactly: value.doubleValue) else { return nil }
                self = .number(exact)
            default:
                return nil
            }
        }

        var json: Any {
            switch self {
            case .number(let value): return value
            case .string(let value): return value
            }
        }
    }

    struct Request: Equatable, Sendable {
        let id: RequestID?
        let method: Method
        /// Who is asking, for the log — `params.client`, free text.
        let client: String?
    }

    /// Why a line isn't a request, with whatever `id` could be read from it so
    /// the error still reaches the call that sent it.
    struct ParseFailure: Error, Equatable, Sendable {
        let id: RequestID?
        let code: ErrorCode
        let message: String
    }

    static func parseRequest(_ line: Data) -> Result<Request, ParseFailure> {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            return .failure(ParseFailure(id: nil, code: .invalidRequest, message: "Each line must be one JSON object."))
        }
        let id = RequestID(json: object["id"])
        guard let name = object["method"] as? String else {
            return .failure(ParseFailure(id: id, code: .invalidRequest, message: "The request has no \"method\"."))
        }
        guard let method = Method(rawValue: name) else {
            return .failure(ParseFailure(id: id, code: .unknownMethod, message: "Unknown method \"\(name)\"."))
        }
        let params = object["params"] as? [String: Any]
        return .success(Request(id: id, method: method, client: params?["client"] as? String))
    }

    static func response(id: RequestID?, result: [String: Any] = [:]) -> Data {
        var object: [String: Any] = ["ok": true, "result": result]
        object["id"] = id?.json
        return line(object)
    }

    static func failure(id: RequestID?, code: ErrorCode, message: String) -> Data {
        var object: [String: Any] = [
            "ok": false,
            "error": ["code": code.rawValue, "message": message],
        ]
        object["id"] = id?.json
        return line(object)
    }

    static func event(_ name: String, _ fields: [String: Any] = [:]) -> Data {
        var object = fields
        object["event"] = name
        return line(object)
    }

    private static func line(_ object: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]))
            ?? Data(#"{"ok":false}"#.utf8)
        data.append(0x0A)
        return data
    }

    /// Reassembles lines from whatever chunks the socket hands over. A line
    /// past `maxLineBytes` sets `overflowed` — the connection is beyond
    /// saving, since there's no telling where its next request starts.
    struct LineSplitter: Sendable {
        private var pending = Data()
        private(set) var overflowed = false

        mutating func append(_ chunk: Data) -> [Data] {
            guard !overflowed else { return [] }
            pending.append(chunk)
            var lines: [Data] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[pending.startIndex..<newline])
                pending = Data(pending[pending.index(after: newline)...])
                let trimmed = line.last == 0x0D ? line.dropLast() : line[...]
                if !trimmed.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) {
                    lines.append(Data(trimmed))
                }
            }
            if pending.count > ExternalAPI.maxLineBytes {
                overflowed = true
                pending = Data()
            }
            return lines
        }
    }
}
