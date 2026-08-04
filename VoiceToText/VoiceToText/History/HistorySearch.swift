import Foundation
import SwiftUI

// MARK: - Date formatting
//
// One source of truth for how a recording's date is written, shared by the row
// label and the search haystack — so typing what you can see on the row always
// matches it.

enum RecordingDateFormat {
    /// What the row shows: "Today at 3:42 PM", "Aug 2, 2026 at 9:10 AM".
    static func rowLabel(_ date: Date) -> String {
        rowFormatter.string(from: date)
    }

    /// The absolute spelling, so "august" finds a recording whose row reads
    /// "Today at 3:42 PM". Never displayed — search only.
    static func searchable(_ date: Date) -> String {
        searchFormatter.string(from: date)
    }

    /// "AUGUST 2026" — the month section header (uppercased at render time).
    static func monthLabel(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    private static let rowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let searchFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()
}

// MARK: - Search

/// History search: a linear in-memory scan, and the match highlighting that
/// makes a hit legible in the row.
///
/// No index, no FTS, no SQLite, no migration — and that is a measured decision,
/// not a shortcut. `RecordingHistoryStore.maxEntries` is a hard **200**, the
/// list lives in memory as a flat array (the on-disk `index.json` is only a
/// cache of it), and the cap is a compile-time constant with no settings UI and
/// no `UserDefaults` key behind it. Scanning 200 entries is microseconds, so
/// there is nothing here for a background actor to do. If that cap ever becomes
/// user-adjustable, this is the file to revisit.
enum HistorySearch {
    /// Case- and diacritic-insensitive, per the brief. `.caseInsensitive`
    /// alone would miss "Munchen" → "München".
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// A query splits on whitespace into terms, and **all** terms must match —
    /// so "kara budget" finds the recording where Kara talked about the budget,
    /// not every recording mentioning either.
    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func isActive(_ query: String) -> Bool {
        !terms(in: query).isEmpty
    }

    /// Narrows `entries` to those matching every term in `query`. An empty or
    /// whitespace-only query returns the input untouched.
    static func filter(_ entries: [RecordingHistoryEntry], query: String) -> [RecordingHistoryEntry] {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return entries }
        return entries.filter { matches($0, terms: terms) }
    }

    static func matches(_ entry: RecordingHistoryEntry, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let stored = storedFields(of: entry)
        // The date fields are the only expensive ones (two `DateFormatter`
        // runs), so they are formatted at most once per entry and only for a
        // term the stored text didn't already answer.
        var dates: [String]?
        for term in terms {
            if stored.contains(where: { $0.range(of: term, options: options) != nil }) { continue }
            let formatted = dates ?? dateFields(of: entry)
            dates = formatted
            guard formatted.contains(where: { $0.range(of: term, options: options) != nil }) else {
                return false
            }
        }
        return true
    }

    /// Everything already in the entry that a query may match: transcript text
    /// (including the alternates a regenerated recording still shows), the
    /// speaker names the user assigned, the model, and the recording type.
    ///
    /// Returned as separate fields rather than one joined string so a match
    /// can't straddle two of them, and so nothing is copied — Swift strings are
    /// COW, so this array is a handful of references.
    static func storedFields(of entry: RecordingHistoryEntry) -> [String] {
        var fields: [String] = [entry.transcript]
        for alternate in entry.alternates ?? [] {
            fields.append(alternate.text)
        }
        if let names = entry.speakerNames {
            fields.append(contentsOf: names.values)
        }
        if let modelName = entry.modelName { fields.append(modelName) }
        if let modelId = entry.modelId { fields.append(modelId) }
        fields.append((entry.source ?? .dictation).displayName)
        return fields
    }

    /// The date, both as the row writes it ("Yesterday at 22:05") and in its
    /// absolute form ("Monday, 3 August 2026") — so "yesterday" and "august"
    /// both find the same recording.
    static func dateFields(of entry: RecordingHistoryEntry) -> [String] {
        [
            RecordingDateFormat.rowLabel(entry.createdAt),
            RecordingDateFormat.searchable(entry.createdAt)
        ]
    }

    // MARK: Highlighting

    /// The matched substrings of `text`, marked with the `accent` token as a
    /// background wash and `ink` on top so the hit stays the most readable
    /// thing in the row.
    ///
    /// A real `AttributedString`, not a re-rendered row: the transcript keeps
    /// its selection, its truncation and its line limit, and the highlight is
    /// just two attributes on the runs that matched.
    static func highlighted(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        let terms = terms(in: query)
        guard !terms.isEmpty else { return attributed }
        for term in terms {
            for found in ranges(of: term, in: text) {
                guard let range = Range(found, in: attributed) else { continue }
                attributed[range].backgroundColor = Palette.accent.opacity(0.22)
                attributed[range].foregroundColor = Palette.ink
            }
        }
        return attributed
    }

    /// Every occurrence of `term` in `text`, left to right. Overlapping matches
    /// are impossible here because the search resumes past each hit.
    static func ranges(of term: String, in text: String) -> [Range<String.Index>] {
        guard !term.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(
                of: term,
                options: options,
                range: searchStart..<text.endIndex
              ) {
            found.append(range)
            // A diacritic-insensitive match can be shorter than the term but
            // never empty; the `index(after:)` arm is a non-termination guard,
            // not an expected path.
            searchStart = range.upperBound > range.lowerBound
                ? range.upperBound
                : text.index(after: range.lowerBound)
        }
        return found
    }
}

// MARK: - Date sections

/// One labelled run of rows in the History list.
struct HistorySection: Identifiable {
    let id: String
    /// Written in sentence case; the header renders it uppercased.
    let title: String
    let entries: [RecordingHistoryEntry]
}

/// Buckets recordings into Today / Yesterday / This Week / by month — the thing
/// that makes a 200-row list readable at all, and the thing search collapses
/// into a single "Results · N" run.
enum HistoryDateGrouping {
    /// `entries` must already be newest-first (the store's invariant); order is
    /// preserved within and across sections.
    static func sections(
        of entries: [RecordingHistoryEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HistorySection] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var buckets: [String: [RecordingHistoryEntry]] = [:]

        for entry in entries {
            let bucket = bucket(for: entry.createdAt, now: now, calendar: calendar)
            if buckets[bucket.id] == nil {
                order.append(bucket.id)
                titles[bucket.id] = bucket.title
            }
            buckets[bucket.id, default: []].append(entry)
        }

        return order.map { id in
            HistorySection(id: id, title: titles[id] ?? id, entries: buckets[id] ?? [])
        }
    }

    private static func bucket(
        for date: Date,
        now: Date,
        calendar: Calendar
    ) -> (id: String, title: String) {
        if calendar.isDateInToday(date) { return ("today", "Today") }
        if calendar.isDateInYesterday(date) { return ("yesterday", "Yesterday") }
        // Same calendar week and genuinely in the past. A future timestamp (a
        // clock that was wrong when the recording landed) falls through to its
        // month rather than claiming to be part of this week.
        if date < now, calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return ("thisWeek", "This Week")
        }
        let title = RecordingDateFormat.monthLabel(date)
        return ("month.\(title)", title)
    }
}
