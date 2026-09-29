import Foundation

/// Pure encode/decode of the History `index.json`, kept Foundation-only so it
/// can be tested without the filesystem or the main actor (see
/// `Tests/HistoryIndexCodecHarness.swift`).
///
/// The index is decoded row by row rather than as one `[RecordingHistoryEntry]`
/// because a single undecodable row used to fail the whole file, and an empty
/// library at launch makes the orphan reaper delete every WAV. A row this
/// build can't read — typically one written by a newer build (an unknown
/// `source`, a new required field) before a downgrade — is kept verbatim as a
/// `PassthroughRow` and written back out, so it survives until a build that
/// understands it runs again.
///
/// The passthrough is per row, not per field: a newer build's row that only
/// adds an optional field still decodes here, and that unknown field is lost
/// the next time this build writes the index.
nonisolated enum HistoryIndexCodec {
    /// A row this build couldn't decode, held as opaque JSON.
    struct PassthroughRow: Sendable, Equatable {
        let json: JSONValue

        /// The row's audio file, when it names one, so its WAV counts as
        /// referenced and is never reaped as an orphan.
        var audioFileName: String? {
            guard case .object(let fields) = json, case .string(let name)? = fields["audioFileName"] else { return nil }
            return name
        }
    }

    struct Decoded: Sendable, Equatable {
        var entries: [RecordingHistoryEntry]
        var passthrough: [PassthroughRow]
    }

    /// Decodes an index file. Throws only when the data isn't a JSON array at
    /// all — the caller treats that as an unreadable index. Any element that
    /// fails to decode as an entry is passed through instead of thrown.
    static func decode(_ data: Data) throws -> Decoded {
        let rows = try decoder().decode([Row].self, from: data)
        var decoded = Decoded(entries: [], passthrough: [])
        for row in rows {
            switch row {
            case .entry(let entry): decoded.entries.append(entry)
            case .passthrough(let json): decoded.passthrough.append(PassthroughRow(json: json))
            }
        }
        return decoded
    }

    /// Encodes entries followed by the passthrough rows, through the one
    /// encoder so every row shares the same pretty, sorted formatting.
    static func encode(entries: [RecordingHistoryEntry], passthrough: [PassthroughRow]) throws -> Data {
        let rows = entries.map(Row.entry) + passthrough.map { Row.passthrough($0.json) }
        return try encoder().encode(rows)
    }

    /// Every WAV the index still points at, passthrough rows included.
    static func referencedAudio(entries: [RecordingHistoryEntry], passthrough: [PassthroughRow]) -> Set<String> {
        Set(entries.map(\.audioFileName)).union(passthrough.compactMap(\.audioFileName))
    }

    // MARK: - Quarantine

    /// Prefix of an index moved aside because it couldn't be read. Its WAVs
    /// stay on disk while one exists, so the library is recoverable by hand.
    static let quarantinePrefix = "index.corrupt-"

    /// File name for an unreadable index moved aside at `date`. UTC and
    /// separator-free so it sorts by time and is safe in any file system.
    static func quarantineFileName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return "\(quarantinePrefix)\(formatter.string(from: date)).json"
    }

    /// Whether the launch sweep may delete unreferenced WAVs. Only after a
    /// clean load (a missing index counts as clean — a fresh install), and
    /// never while a quarantined index exists: its rows are unknown, so every
    /// WAV could be one of theirs.
    static func mayReapOrphans(loadWasClean: Bool, directoryFileNames: [String]) -> Bool {
        loadWasClean && !directoryFileNames.contains {
            $0.hasPrefix(quarantinePrefix) && $0.hasSuffix(".json")
        }
    }

    /// Whether the launch sweep may delete one unreferenced WAV: only when it
    /// landed (`modified`) strictly before index.json was last written. A WAV written
    /// after the last successful index write may belong to an entry whose own
    /// index write failed (a full disk still lets a same-volume move land), so
    /// it's kept. An unknown date on either side keeps it too — with no index
    /// on disk there is nothing to say the WAV is stale.
    static func mayReapOrphanWAV(modified: Date?, indexModified: Date?) -> Bool {
        guard let modified, let indexModified else { return false }
        return modified < indexModified
    }

    // MARK: - Rows

    /// One element of the index array: an entry when it decodes, otherwise the
    /// raw JSON. Retrying on the same decoder keeps the date strategy.
    private enum Row: Codable {
        case entry(RecordingHistoryEntry)
        case passthrough(JSONValue)

        init(from decoder: Decoder) throws {
            if let entry = try? RecordingHistoryEntry(from: decoder) {
                self = .entry(entry)
            } else {
                self = .passthrough(try JSONValue(from: decoder))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .entry(let entry): try entry.encode(to: encoder)
            case .passthrough(let json): try json.encode(to: encoder)
            }
        }
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension HistoryIndexCodec {
    /// Any JSON value, lossless enough to write a passthrough row back out
    /// equivalent to how it was read. Integers are kept apart from doubles so an
    /// id-like number never picks up a fraction or loses precision.
    nonisolated enum JSONValue: Codable, Sendable, Equatable {
        case null
        case bool(Bool)
        case int(Int64)
        case double(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            // Int64 before Double so integers stay integers (`1.0` decodes as
            // an Int and writes back as `1`, the same JSON number). Bools and
            // numbers can't be confused: JSONDecoder refuses either as the other.
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int64.self) {
                self = .int(value)
            } else if let value = try? container.decode(Double.self) {
                self = .double(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else {
                self = .object(try container.decode([String: JSONValue].self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case .bool(let value): try container.encode(value)
            case .int(let value): try container.encode(value)
            case .double(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            }
        }
    }
}
