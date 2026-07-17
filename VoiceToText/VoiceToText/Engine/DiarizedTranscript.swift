import Foundation

/// Pure parsing and formatting core for OpenAI's `gpt-4o-transcribe-diarize`
/// model (`response_format=diarized_json`). Foundation-only and `nonisolated`
/// so it can be unit-tested standalone (see `Tests/DiarizedTranscriptHarness`).
///
/// The engine drives a whole `transcribe()` call — possibly several sequential
/// API requests for a long recording — through these helpers: it accumulates
/// every request's `Segment`s, feeds each request's audio + segments to
/// `referenceClips` to keep speaker numbering consistent across requests, and
/// calls `format` once on the accumulated segments for the final transcript.
nonisolated enum DiarizedTranscript {
    /// One diarized span as returned by the API (or synthesized from a
    /// text-only fallback). `speaker` is the *raw* label — "A"/"B",
    /// "speaker_0", or a canonical name we pinned via `known_speaker_names[]`.
    struct Segment: Equatable {
        var speaker: String
        var text: String
        var start: Double?
        var end: Double?

        init(speaker: String, text: String, start: Double? = nil, end: Double? = nil) {
            self.speaker = speaker
            self.text = text
            self.start = start
            self.end = end
        }
    }

    /// Raw label used for a chunk that only yielded a top-level `text` (no
    /// per-speaker segments). Stable across chunks so consecutive text-only
    /// chunks merge into a single unlabeled block.
    static let textFallbackSpeaker = "\u{2063}single"

    // MARK: Decode

    private struct Response: Decodable {
        struct RawSegment: Decodable {
            let speaker: String?
            let text: String?
            let start: Double?
            let end: Double?
        }
        let segments: [RawSegment]?
        let text: String?
    }

    /// Defensively decodes one `diarized_json` response body into segments.
    /// Prefers `segments`; if they're missing or empty, falls back to a single
    /// segment carrying the top-level `text`. Throws
    /// `TranscriptionEngineError.transcriptionFailed` when neither is present
    /// (or the payload isn't valid JSON at all).
    static func parse(_ data: Data) throws -> [Segment] {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TranscriptionEngineError.transcriptionFailed("Could not parse OpenAI response")
        }

        if let raw = response.segments, !raw.isEmpty {
            return raw.map {
                Segment(
                    speaker: $0.speaker ?? textFallbackSpeaker,
                    text: $0.text ?? "",
                    start: $0.start,
                    end: $0.end
                )
            }
        }

        if let text = response.text,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [Segment(speaker: textFallbackSpeaker, text: text)]
        }

        throw TranscriptionEngineError.transcriptionFailed("Could not parse OpenAI response")
    }

    // MARK: Speaker labeling

    /// Maps raw speaker labels to canonical "Speaker N" names in order of first
    /// appearance. A raw label that is *itself* an already-assigned canonical
    /// name (i.e. a name we pinned via `known_speaker_names[]`) maps to itself
    /// rather than being renumbered — this is what keeps numbering stable across
    /// the sequential requests of one long recording.
    struct SpeakerLabelMap {
        /// Canonical names in first-appearance order.
        private(set) var order: [String] = []
        private var map: [String: String] = [:]

        init() {}

        mutating func canonical(for rawLabel: String) -> String {
            if let existing = map[rawLabel] { return existing }
            let canonicalName: String
            if order.contains(rawLabel) {
                canonicalName = rawLabel
            } else {
                canonicalName = "Speaker \(order.count + 1)"
                order.append(canonicalName)
            }
            map[rawLabel] = canonicalName
            return canonicalName
        }
    }

    // MARK: Canonicalize

    /// Rewrites one chunk's freshly-parsed segments to canonical "Speaker N"
    /// names, then hands the canonicalized segments straight to `referenceClips`
    /// / `format`. Raw labels in a `diarized_json` response are only meaningful
    /// *within that response* — the API restarts unknown-speaker letters ("A",
    /// "B", …) on each request — so an unknown raw label must be treated as a
    /// distinct speaker per chunk. Two labels stay global: a raw label that is
    /// already an assigned canonical name (pinned via `known_speaker_names[]`)
    /// maps to itself, and `textFallbackSpeaker` stays stable so consecutive
    /// text-only chunks merge. Empty segments are dropped here (as `format`
    /// would), keeping the numbering `format` derives identical to this one.
    static func canonicalize(
        segments: [Segment],
        chunk: Int,
        labelMap: inout SpeakerLabelMap
    ) -> [Segment] {
        var result: [Segment] = []
        result.reserveCapacity(segments.count)
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let key = scopedKey(rawLabel: segment.speaker, chunk: chunk, order: labelMap.order)
            var rewritten = segment
            rewritten.speaker = labelMap.canonical(for: key)
            result.append(rewritten)
        }
        return result
    }

    /// The map key for a raw label: globally stable for pinned canonical names
    /// and the text-only fallback, chunk-scoped for everything else.
    private static func scopedKey(rawLabel: String, chunk: Int, order: [String]) -> String {
        if rawLabel == textFallbackSpeaker { return rawLabel }
        if order.contains(rawLabel) { return rawLabel }
        return "\(chunk)#\(rawLabel)"
    }

    // MARK: Format

    /// Builds the final transcript from all accumulated segments. Assigns
    /// canonical speaker names, merges consecutive same-speaker segments into
    /// one block, and drops empty text. With exactly one distinct speaker the
    /// result is plain text (no labels) so dictation stays clean; otherwise each
    /// turn is a `Speaker N: …` line joined by newlines.
    static func format(segments: [Segment]) -> String {
        var labelMap = SpeakerLabelMap()
        var blocks: [(speaker: String, text: String)] = []

        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let canonical = labelMap.canonical(for: segment.speaker)
            if let lastIndex = blocks.indices.last, blocks[lastIndex].speaker == canonical {
                blocks[lastIndex].text += " " + text
            } else {
                blocks.append((canonical, text))
            }
        }

        guard !blocks.isEmpty else { return "" }

        let distinct = Set(blocks.map(\.speaker))
        if distinct.count < 2 {
            return blocks.map(\.text).joined(separator: " ")
        }
        return blocks.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    // MARK: Reference clips

    /// Updates the per-speaker reference clips used to pin speaker identities in
    /// the *next* request. For each canonical speaker among the first four seen
    /// so far, picks that speaker's longest segment in this chunk, clamps it to
    /// 10 s, and skips it if under 2 s (keeping any previously captured clip).
    /// Advances `labelMap` for every non-empty segment in this chunk so the
    /// numbering matches `format`'s. Returns canonical name → Float slice; the
    /// engine WAV-encodes + base64s each slice.
    static func referenceClips(
        fromChunk samples: [Float],
        segments: [Segment],
        sampleRate: Int,
        labelMap: inout SpeakerLabelMap,
        previous: [String: [Float]]
    ) -> [String: [Float]] {
        var longest: [String: Segment] = [:]
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let canonical = labelMap.canonical(for: segment.speaker)
            guard let segmentDuration = duration(of: segment) else { continue }
            if let current = longest[canonical], let currentDuration = duration(of: current),
               currentDuration >= segmentDuration {
                continue
            }
            longest[canonical] = segment
        }

        let allowed = Set(labelMap.order.prefix(4))
        var result = previous
        for (canonical, segment) in longest {
            guard allowed.contains(canonical),
                  let start = segment.start,
                  let end = segment.end,
                  end - start >= 2.0 else { continue }
            let clampedEnd = min(end, start + 10.0)
            let startIndex = max(0, Int(start * Double(sampleRate)))
            let endIndex = min(samples.count, Int(clampedEnd * Double(sampleRate)))
            guard endIndex > startIndex else { continue }
            result[canonical] = Array(samples[startIndex..<endIndex])
        }
        return result
    }

    private static func duration(of segment: Segment) -> Double? {
        guard let start = segment.start, let end = segment.end, end > start else { return nil }
        return end - start
    }
}
