import Foundation

/// The identity and version rules a downloaded update must pass before it may
/// replace the running app. The signature check proves who built the bundle;
/// these prove it's this app and a step forward: a genuinely signed but older
/// release (a downgrade to a version with a known bug) or a sibling build (the
/// Dev variant, which shares the Developer ID) must never be swapped in over
/// the app holding the Microphone, Accessibility and Screen Recording grants.
///
/// Foundation-only and `nonisolated` so the updater's background install path
/// and the harness share one definition.
nonisolated enum UpdateEligibility {
    enum Verdict: Equatable {
        case eligible
        /// The bundle identifies as another app, or one side has no identifier
        /// to compare (never assume a match).
        case differentApp(candidate: String?, running: String?)
        /// Not strictly newer than the running version: a downgrade, the same
        /// version again, or a version string with nothing to compare.
        case notNewer(candidate: String?, running: String)
    }

    static func verdict(
        candidateBundleID: String?,
        candidateVersion: String?,
        runningBundleID: String?,
        runningVersion: String
    ) -> Verdict {
        guard let candidateBundleID, let runningBundleID,
              !runningBundleID.isEmpty, candidateBundleID == runningBundleID else {
            return .differentApp(candidate: candidateBundleID, running: runningBundleID)
        }
        guard let candidateVersion,
              isNewer(latest: stripV(candidateVersion), current: stripV(runningVersion)) else {
            return .notNewer(candidate: candidateVersion, running: runningVersion)
        }
        return .eligible
    }

    // MARK: - Version comparison

    /// Compares the first three numeric components. A missing or non-numeric
    /// component counts as 0, so an unreadable version is never newer.
    static func isNewer(latest: String, current: String) -> Bool {
        let l = parse(latest)
        let c = parse(current)
        for i in 0..<3 where l[i] != c[i] {
            return l[i] > c[i]
        }
        return false
    }

    /// Release tags are `v0.1.2`; bundle versions are `0.1.2`.
    static func stripV(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    private static func parse(_ version: String) -> [Int] {
        // Strip any prerelease suffix like "-beta.1"
        let clean = version.split(separator: "-").first.map(String.init) ?? version
        var parts = clean.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        return Array(parts.prefix(3))
    }
}
