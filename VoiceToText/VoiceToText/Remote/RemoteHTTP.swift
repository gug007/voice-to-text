import Foundation

/// The little HTTP/1.1 the Mac's remote server speaks: one request per
/// connection (`Connection: close`), bodies only by Content-Length. Pure and
/// Foundation-only so the harness covers parsing, framing and routing.
///
/// Hand-rolled rather than built on a framework because the transport is a
/// file descriptor handed over by libtailscale, not a socket Network.framework
/// can adopt, and four routes don't justify a dependency.
nonisolated struct RemoteHTTPRequest: Equatable, Sendable {
    let method: String
    /// The path without its query string.
    let path: String
    let query: String?
    /// Lowercased names. A repeated header keeps its last value.
    let headers: [String: String]
    let body: Data

    func queryValue(_ name: String) -> String? {
        guard let query else { return nil }
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts[0] == name { return parts.count > 1 ? String(parts[1]) : "" }
        }
        return nil
    }
}

nonisolated enum RemoteHTTPParser {
    /// The phone sends a few hundred bytes of headers; anything near this is
    /// not the phone.
    static let maxHeaderBytes = 16 * 1024
    /// No route takes a body today; start and stop send none.
    static let maxBodyBytes = 64 * 1024

    enum Outcome: Equatable, Sendable {
        /// Keep reading: the request isn't all here yet.
        case incomplete
        case complete(RemoteHTTPRequest)
        /// Answer with this status and close.
        case invalid(status: Int, reason: String)
    }

    private static let headerTerminator = Data("\r\n\r\n".utf8)

    static func parse(_ buffer: Data) -> Outcome {
        guard let end = buffer.range(of: headerTerminator) else {
            return buffer.count > maxHeaderBytes
                ? .invalid(status: 431, reason: "Request headers are too large.")
                : .incomplete
        }
        let headerBytes = buffer[buffer.startIndex..<end.lowerBound]
        guard headerBytes.count <= maxHeaderBytes else {
            return .invalid(status: 431, reason: "Request headers are too large.")
        }
        guard let head = String(data: headerBytes, encoding: .utf8) else {
            return .invalid(status: 400, reason: "Request headers aren't text.")
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return .invalid(status: 400, reason: "Malformed request line.")
        }
        let method = String(parts[0])
        let target = String(parts[1])
        let version = String(parts[2])
        guard !method.isEmpty, method.allSatisfy({ $0.isASCII && $0.isUppercase }) else {
            return .invalid(status: 400, reason: "Malformed method.")
        }
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
            return .invalid(status: 505, reason: "Only HTTP/1.1 is supported.")
        }
        guard target.hasPrefix("/") else {
            return .invalid(status: 400, reason: "Malformed request target.")
        }

        var headers: [String: String] = [:]
        for line in lines {
            if line.isEmpty { continue }
            guard let first = line.first, first != " ", first != "\t",
                  let colon = line.firstIndex(of: ":") else {
                return .invalid(status: 400, reason: "Malformed header.")
            }
            let name = line[..<colon]
            guard !name.isEmpty, !name.contains(where: { $0 == " " || $0 == "\t" }) else {
                return .invalid(status: 400, reason: "Malformed header name.")
            }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let key = name.lowercased()
            if key == "content-length", let previous = headers[key], previous != value {
                return .invalid(status: 400, reason: "Conflicting Content-Length.")
            }
            headers[key] = value
        }

        if headers["transfer-encoding"] != nil {
            return .invalid(status: 501, reason: "Chunked request bodies aren't supported.")
        }
        var length = 0
        if let raw = headers["content-length"] {
            guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }), raw.count <= 9, let value = Int(raw) else {
                return .invalid(status: 400, reason: "Malformed Content-Length.")
            }
            guard value <= maxBodyBytes else {
                return .invalid(status: 413, reason: "Request body is too large.")
            }
            length = value
        }
        let bodyStart = end.upperBound
        guard buffer.endIndex - bodyStart >= length else { return .incomplete }
        let body = Data(buffer[bodyStart..<(bodyStart + length)])

        let path: String
        let query: String?
        if let mark = target.firstIndex(of: "?") {
            path = String(target[..<mark])
            query = String(target[target.index(after: mark)...])
        } else {
            path = target
            query = nil
        }
        return .complete(RemoteHTTPRequest(method: method, path: path, query: query, headers: headers, body: body))
    }
}

/// A reply: a status, a content type and either bytes in memory or a file
/// the connection streams from disk in chunks (a conversation's audio can be
/// an hour long).
nonisolated struct RemoteHTTPResponse: Sendable {
    enum Body: Sendable {
        case data(Data)
        case file(URL, length: Int64)
        case liveAudio(LiveAudioListener)
    }

    let status: Int
    let contentType: String
    let body: Body

    var contentLength: Int64? {
        switch body {
        case .data(let data): return Int64(data.count)
        case .file(_, let length): return length
        case .liveAudio: return nil
        }
    }

    static func json<Value: Encodable>(_ value: Value, status: Int = 200) -> RemoteHTTPResponse {
        do {
            let data = try RemoteProtocol.makeEncoder().encode(value)
            return RemoteHTTPResponse(status: status, contentType: "application/json", body: .data(data))
        } catch {
            return .error(500, "The reply couldn't be encoded.")
        }
    }

    static func liveAudio(_ listener: LiveAudioListener) -> RemoteHTTPResponse {
        RemoteHTTPResponse(status: 200, contentType: LiveAudioWire.contentType, body: .liveAudio(listener))
    }

    static func error(_ status: Int, _ message: String) -> RemoteHTTPResponse {
        let data = (try? RemoteProtocol.makeEncoder().encode(RemoteErrorBody(error: message))) ?? Data()
        return RemoteHTTPResponse(status: status, contentType: "application/json", body: .data(data))
    }

    /// The status line and headers, ending in the blank line.
    func head() -> Data {
        var text = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        text += "Content-Type: \(contentType)\r\n"
        if let contentLength { text += "Content-Length: \(contentLength)\r\n" }
        text += "Cache-Control: no-store\r\n"
        text += "Connection: close\r\n\r\n"
        return Data(text.utf8)
    }

    static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 413: return "Content Too Large"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 503: return "Service Unavailable"
        case 505: return "HTTP Version Not Supported"
        default: return "Status \(status)"
        }
    }
}

/// The server's routes, matched from a request's method and path.
nonisolated enum RemoteRoute: Equatable, Sendable {
    case status
    case startConversation
    case stopConversation
    case liveAudio
    case conversations
    case conversation(UUID)
    case audio(UUID)

    enum Mismatch: Error, Equatable {
        case notFound
        case methodNotAllowed
    }

    static func match(method: String, path: String) -> Result<RemoteRoute, Mismatch> {
        let route: RemoteRoute
        let expected: String
        switch path {
        case RemoteProtocol.Path.status:
            (route, expected) = (.status, "GET")
        case RemoteProtocol.Path.startConversation:
            (route, expected) = (.startConversation, "POST")
        case RemoteProtocol.Path.stopConversation:
            (route, expected) = (.stopConversation, "POST")
        case RemoteProtocol.Path.liveAudio:
            (route, expected) = (.liveAudio, "GET")
        case RemoteProtocol.Path.conversations:
            (route, expected) = (.conversations, "GET")
        default:
            let prefix = RemoteProtocol.Path.conversations + "/"
            guard path.hasPrefix(prefix) else { return .failure(.notFound) }
            let rest = path.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
            guard let first = rest.first, let id = UUID(uuidString: String(first)) else {
                return .failure(.notFound)
            }
            switch rest.count {
            case 1: (route, expected) = (.conversation(id), "GET")
            case 2 where rest[1] == "audio": (route, expected) = (.audio(id), "GET")
            default: return .failure(.notFound)
            }
        }
        return method == expected ? .success(route) : .failure(.methodNotAllowed)
    }
}
