import Foundation

/// Why a local model's download or load failed, in one plain sentence. The
/// SDKs bury the cause in types they don't export, so errors are read structurally.
nonisolated enum ModelDownloadFailure {
    enum Cause: Equatable, Sendable {
        case cancelled
        case offline
        case timedOut
        case diskFull(neededBytes: Int64?, freeBytes: Int64?)
        /// `status` is nil when the server never answered.
        case server(status: Int?)
        case stalled
        case other(String)
    }

    static func cause(
        of error: Error,
        isOffline: Bool = false,
        neededBytes: Int64? = nil,
        freeBytes: Int64? = nil
    ) -> Cause {
        var evidence = Evidence()
        evidence.collect(error, depth: 0)

        if evidence.isCancelled { return .cancelled }
        let lowOnDisk = neededBytes.flatMap { needed in freeBytes.map { $0 < needed } } ?? false
        if evidence.isOutOfSpace {
            return .diskFull(neededBytes: neededBytes, freeBytes: freeBytes)
        }
        if isOffline || evidence.isOffline { return .offline }
        if evidence.isTimedOut { return .timedOut }
        if let status = evidence.httpStatus { return .server(status: status) }
        if evidence.isUnreachable { return .server(status: nil) }
        if lowOnDisk { return .diskFull(neededBytes: neededBytes, freeBytes: freeBytes) }
        return .other(error.localizedDescription)
    }

    /// The row's sentence; nil for a cancel, which is not a failure.
    static func sentence(for cause: Cause, formatBytes: (Int64) -> String) -> String? {
        switch cause {
        case .cancelled:
            return nil
        case .offline:
            return "You appear to be offline."
        case .timedOut:
            return "The connection timed out."
        case .diskFull(let needed?, let free?):
            return "Not enough disk space: needs \(formatBytes(needed)), \(formatBytes(free)) free."
        case .diskFull:
            return "Not enough disk space on this Mac."
        case .server(nil):
            return "Couldn't reach the download server."
        case .server(let status?):
            switch status {
            case 429: return "The download server is busy (HTTP 429). Try again later."
            case 404: return "The model wasn't found on the download server (HTTP 404)."
            case 500...599: return "The download server is unavailable (HTTP \(status))."
            default: return "The download server refused the request (HTTP \(status))."
            }
        case .stalled:
            return "The download stopped responding."
        case .other(let description):
            return firstSentence(of: description) ?? "The download failed."
        }
    }

    /// The first sentence of `text`, ending in its own punctuation (or a full
    /// stop when it has none), and never longer than `limit` characters.
    static func firstSentence(of text: String, limit: Int = 140) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var sentence = trimmed
        if let line = trimmed.split(whereSeparator: \.isNewline).first {
            sentence = String(line)
        }
        if let end = sentence.range(of: #"[.!?](?=\s)"#, options: .regularExpression) {
            sentence = String(sentence[..<end.upperBound])
        }
        if sentence.count > limit {
            sentence = String(sentence.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
        }
        if let last = sentence.last, !".!?…".contains(last) { sentence += "." }
        return sentence
    }

    private struct Evidence {
        var isCancelled = false
        var isOffline = false
        var isTimedOut = false
        var isUnreachable = false
        var isOutOfSpace = false
        var httpStatus: Int?

        private static let maxDepth = 6

        mutating func collect(_ error: Error, depth: Int) {
            guard depth < Self.maxDepth else { return }
            if error is CancellationError { isCancelled = true }
            let ns = error as NSError
            note(domain: ns.domain, code: ns.code)
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
                collect(underlying, depth: depth + 1)
            }
            reflect(Mirror(reflecting: error), depth: depth + 1)
        }

        private mutating func reflect(_ mirror: Mirror, depth: Int) {
            guard depth < Self.maxDepth else { return }
            for child in mirror.children {
                if let nested = child.value as? Error {
                    collect(nested, depth: depth)
                } else if let status = child.value as? Int,
                          child.label?.lowercased().contains("status") == true,
                          (100...599).contains(status) {
                    httpStatus = httpStatus ?? status
                } else {
                    reflect(Mirror(reflecting: child.value), depth: depth + 1)
                }
            }
        }

        private mutating func note(domain: String, code: Int) {
            switch domain {
            case NSURLErrorDomain:
                switch code {
                case NSURLErrorCancelled:
                    isCancelled = true
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                     NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff:
                    isOffline = true
                case NSURLErrorTimedOut:
                    isTimedOut = true
                case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
                     NSURLErrorDNSLookupFailed, NSURLErrorBadServerResponse:
                    isUnreachable = true
                default:
                    break
                }
            case NSCocoaErrorDomain:
                if code == NSFileWriteOutOfSpaceError { isOutOfSpace = true }
            case NSPOSIXErrorDomain:
                switch code {
                case Int(ENOSPC): isOutOfSpace = true
                case Int(ENETDOWN), Int(ENETUNREACH): isOffline = true
                case Int(ETIMEDOUT): isTimedOut = true
                case Int(ECANCELED): isCancelled = true
                default: break
                }
            case "HTTP":
                if (100...599).contains(code) { httpStatus = httpStatus ?? code }
            default:
                break
            }
        }
    }
}
