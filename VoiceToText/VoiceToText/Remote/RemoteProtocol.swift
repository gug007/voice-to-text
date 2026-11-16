import Foundation

/// The wire contract between the Mac app and the iPhone app's "Mac" features:
/// the port, the paths and every JSON body, in one Foundation-only file that
/// both targets compile (Mobile/project.yml lists it) and the harness tests.
///
/// The Mac serves plain HTTP/1.1 on `port`. Over Tailscale the transport is
/// already WireGuard-encrypted end to end and the Mac checks every caller's
/// identity (`RemoteAccessPolicy`), so the HTTP layer adds neither TLS nor a
/// token. `version` goes up only on a change an older phone would misread;
/// adding an optional field doesn't need it.
nonisolated enum RemoteProtocol {
    static let version = 1
    /// Fixed so the phone never has to discover it. Unassigned by IANA and
    /// unused by anything else in this app.
    static let port: UInt16 = 47610

    enum Path {
        static let status = "/v1/status"
        static let startConversation = "/v1/conversation/start"
        static let stopConversation = "/v1/conversation/stop"
        static let liveAudio = "/v1/conversation/live"
        static let conversations = "/v1/conversations"

        static func conversation(_ id: UUID) -> String {
            "\(conversations)/\(id.uuidString)"
        }

        static func audio(_ id: UUID) -> String {
            "\(conversation(id))/audio"
        }
    }

    /// Dates as seconds since 1970: both ends are Swift, and it round-trips
    /// sub-second precision that ISO 8601 would drop.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// `GET /v1/status`, and the reply to start and stop: the Mac's conversation
/// recorder as the phone shows it.
nonisolated struct RemoteStatus: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case idle
        case recording
        case transcribing
        /// Transcribing a file dropped onto the Mac. The phone shows it as
        /// transcribing; it is its own case so the Mac never claims a
        /// recording it isn't making.
        case importing
        case error
    }

    var state: State
    /// Seconds recorded so far; 0 unless recording.
    var elapsed: Double
    /// The error text in `.error`; the last save confirmation while idle.
    var message: String?
    /// The Mac's own name, for the phone's card.
    var mac: String
    var appVersion: String
    var `protocol`: Int
    var liveListen: Bool? = nil
    var listeners: Int? = nil
}

/// One conversation in `GET /v1/conversations`: enough for a list row, so
/// the list never carries every transcript in full.
nonisolated struct RemoteConversationRow: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let durationSeconds: Double
    /// The transcript's opening, whitespace collapsed; empty when untranscribed.
    let preview: String
    let hasSummary: Bool
    let hasActionItems: Bool
    let isUntranscribed: Bool
    let modelName: String?

    /// Long enough for the two lines a row shows at the largest phone width.
    static let previewLength = 160

    init(
        id: UUID,
        createdAt: Date,
        durationSeconds: Double,
        preview: String,
        hasSummary: Bool,
        hasActionItems: Bool,
        isUntranscribed: Bool,
        modelName: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.preview = preview
        self.hasSummary = hasSummary
        self.hasActionItems = hasActionItems
        self.isUntranscribed = isUntranscribed
        self.modelName = modelName
    }

    init(entry: RecordingHistoryEntry) {
        let untranscribed = entry.transcriptIsPlaceholder
        self.init(
            id: entry.id,
            createdAt: entry.createdAt,
            durationSeconds: entry.durationSeconds,
            preview: untranscribed ? "" : Self.preview(of: entry.transcript),
            hasSummary: entry.summary != nil,
            hasActionItems: !(entry.actionItems?.items.isEmpty ?? true),
            isUntranscribed: untranscribed,
            modelName: entry.modelName
        )
    }

    static func preview(of transcript: String) -> String {
        let collapsed = transcript
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard collapsed.count > previewLength else { return collapsed }
        return String(collapsed.prefix(previewLength)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// `GET /v1/conversations`, newest first. An object rather than a bare
/// array so a later field (paging, a total) is not a breaking change.
nonisolated struct RemoteConversationList: Codable, Equatable, Sendable {
    let conversations: [RemoteConversationRow]

    /// Only conversations: dictations stay on the Mac.
    static func make(from entries: [RecordingHistoryEntry]) -> RemoteConversationList {
        RemoteConversationList(conversations: entries
            .filter { $0.source == .meeting }
            .sorted { $0.createdAt > $1.createdAt }
            .map(RemoteConversationRow.init(entry:)))
    }
}

/// The body of every 4xx/5xx reply.
nonisolated struct RemoteErrorBody: Codable, Equatable, Sendable {
    let error: String
}

/// Tailscale host names for the two apps. Fixed prefixes are how the phone
/// tells a VoiceToText Mac from every other machine on the tailnet; the rest
/// is the device's own name, so two Macs are told apart in the picker and in
/// the Tailscale admin console.
nonisolated enum RemoteHostName {
    static let macPrefix = "voicetotext-mac"
    static let phonePrefix = "voicetotext-iphone"

    /// A DNS label is at most 63 characters.
    static let maxLength = 63

    static func mac(computerName: String) -> String {
        make(prefix: macPrefix, deviceName: computerName)
    }

    /// iOS reports a generic "iPhone" for the device name unless the app holds
    /// an entitlement it doesn't, and "voicetotext-iphone-iphone" says
    /// nothing more than the prefix does.
    static func phone(deviceName: String) -> String {
        let name = sanitize(deviceName)
        if name == "iphone" || name == "ipad" { return phonePrefix }
        return make(prefix: phonePrefix, deviceName: deviceName)
    }

    /// Whether a peer's host name is a VoiceToText Mac's.
    static func isMac(_ hostName: String) -> Bool {
        let name = hostName.lowercased()
        return name == macPrefix || name.hasPrefix(macPrefix + "-")
    }

    /// "Gurgen’s MacBook Pro" → "gurgens-macbook-pro": Latin letters (accents
    /// folded, other scripts transliterated), digits and single hyphens.
    static func sanitize(_ name: String) -> String {
        let latin = name.applyingTransform(.toLatin, reverse: false) ?? name
        let folded = latin.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var out = ""
        var pendingHyphen = false
        for scalar in folded.unicodeScalars {
            switch scalar {
            case "a"..."z", "0"..."9":
                if pendingHyphen, !out.isEmpty { out.append("-") }
                pendingHyphen = false
                out.unicodeScalars.append(scalar)
            case "A"..."Z":
                if pendingHyphen, !out.isEmpty { out.append("-") }
                pendingHyphen = false
                out.unicodeScalars.append(Unicode.Scalar(scalar.value + 32)!)
            case "'", "\u{2019}", "\u{2018}", "`":
                continue
            default:
                pendingHyphen = true
            }
        }
        return out
    }

    private static func make(prefix: String, deviceName: String) -> String {
        let name = sanitize(deviceName)
        guard !name.isEmpty else { return prefix }
        let room = maxLength - prefix.count - 1
        var trimmed = String(name.prefix(room))
        while trimmed.hasSuffix("-") { trimmed.removeLast() }
        return trimmed.isEmpty ? prefix : "\(prefix)-\(trimmed)"
    }
}
