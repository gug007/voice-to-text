import Foundation

/// When the updater checks again and how it offers what it finds.
///
/// The app is a login item that can run for weeks without relaunching, so the
/// first check after launch is often the only one anybody sees. It used to be
/// the only one that could offer an update at all, and a launch check that
/// failed (offline at login, GitHub's unauthenticated rate limit on a shared
/// IP) went quiet for a full day. Someone stayed six releases behind that way.
/// These rules keep that from happening: failures retry on a short backoff,
/// any answered check can surface an update, and the modal prompt still comes
/// at most once per version per session.
///
/// Foundation-only and `nonisolated` so the updater and the harness share one
/// definition.
nonisolated enum UpdateCheckPolicy {
    /// The cadence once a check has been answered.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Waits after the first, second and third failure in a row. After that
    /// the normal cadence takes over, and only a returning network connection
    /// brings the next check forward.
    static let retryDelays: [TimeInterval] = [60, 5 * 60, 30 * 60]

    /// The least time between two checks that a network change may trigger,
    /// so a flapping connection can't turn into a stream of requests.
    static let minimumNetworkRetrySpacing: TimeInterval = 30

    // MARK: - Failures

    enum Failure: Equatable {
        /// No connection, or the server couldn't be reached.
        case offline
        /// GitHub's 403/429 for unauthenticated callers. `retryAfter` is the
        /// wait GitHub asked for, when it said.
        case rateLimited(retryAfter: TimeInterval?)
        /// Worth trying again soon: a server error, a dropped request, or a
        /// release published before its DMG finished uploading.
        case transient
        /// Won't change by asking again soon: another 4xx, or a response
        /// that couldn't be read.
        case permanent
    }

    static func failure(forHTTPStatus status: Int, retryAfter: TimeInterval?) -> Failure {
        switch status {
        case 403, 429:
            return .rateLimited(retryAfter: retryAfter)
        case 408, 500...599:
            return .transient
        default:
            return .permanent
        }
    }

    static func failure(for error: Error) -> Failure {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .timedOut,
                 .internationalRoamingOff, .dataNotAllowed, .callIsActive:
                return .offline
            default:
                return .transient
            }
        }
        if error is DecodingError { return .permanent }
        return .transient
    }

    /// The wait GitHub asked for: `Retry-After` (seconds or an HTTP date), or
    /// else `X-RateLimit-Reset` (epoch seconds) when no requests remain. Nil
    /// when neither says anything usable.
    static func retryAfter(
        retryAfterHeader: String?,
        rateLimitRemaining: String?,
        rateLimitReset: String?,
        now: Date
    ) -> TimeInterval? {
        if let raw = retryAfterHeader?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            if let seconds = TimeInterval(raw), seconds >= 0 {
                return seconds
            }
            if let date = httpDate(raw) {
                return max(0, date.timeIntervalSince(now))
            }
        }
        if rateLimitRemaining?.trimmingCharacters(in: .whitespaces) == "0",
           let raw = rateLimitReset?.trimmingCharacters(in: .whitespaces),
           let reset = TimeInterval(raw) {
            return max(0, reset - now.timeIntervalSince1970)
        }
        return nil
    }

    private static func httpDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: string)
    }

    // MARK: - Scheduling

    /// How long to wait before the next background check. `failure` is the
    /// last check's failure (nil when it was answered) and
    /// `consecutiveFailures` counts it.
    static func nextCheckDelay(after failure: Failure?, consecutiveFailures: Int) -> TimeInterval {
        guard let failure else { return checkInterval }
        let backoff: TimeInterval
        switch failure {
        case .permanent:
            backoff = checkInterval
        case .offline, .transient, .rateLimited:
            let index = max(consecutiveFailures, 1) - 1
            backoff = index < retryDelays.count ? retryDelays[index] : checkInterval
        }
        guard case .rateLimited(let retryAfter?) = failure else { return backoff }
        // Never sooner than GitHub asked, never later than the normal cadence.
        return min(max(backoff, retryAfter), checkInterval)
    }

    /// The earliest moment a check may run after this failure, whatever wakes
    /// the updater: the end of a rate limit GitHub announced.
    static func notBefore(after failure: Failure?, now: Date) -> Date? {
        guard case .rateLimited(let retryAfter?) = failure else { return nil }
        return now.addingTimeInterval(min(retryAfter, checkInterval))
    }

    /// Whether a network connection coming back should run the next check
    /// now instead of waiting out the backoff. Only after a failure, never
    /// inside a rate limit GitHub announced, and never right on the heels of
    /// the last attempt.
    static func shouldCheckWhenNetworkReturns(
        lastFailure: Failure?,
        notBefore: Date?,
        lastAttemptAt: Date?,
        now: Date
    ) -> Bool {
        guard let lastFailure, lastFailure != .permanent else { return false }
        if let notBefore, now < notBefore { return false }
        if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < minimumNetworkRetrySpacing {
            return false
        }
        return true
    }

    // MARK: - Offering

    enum Offer: Equatable {
        /// Nothing to show: not newer, or skipped.
        case nothing
        /// The persistent indicator only (menu bar item, sidebar badge).
        case indicate
        /// The modal prompt, plus the indicator.
        case prompt
    }

    /// What an answered background check that found `latest` should do.
    /// The modal belongs to the session's first answered check, which is
    /// the launch check or the retry that stands in for it when that failed;
    /// later finds wait quietly behind the indicator. Either way one version
    /// is prompted for at most once a session, and a skipped one never.
    static func offer(
        latest: String,
        running: String,
        skippedVersion: String?,
        promptedVersions: Set<String>,
        isFirstAnsweredCheck: Bool
    ) -> Offer {
        let latest = UpdateEligibility.stripV(latest)
        guard UpdateEligibility.isNewer(latest: latest, current: UpdateEligibility.stripV(running)) else {
            return .nothing
        }
        if let skippedVersion, UpdateEligibility.stripV(skippedVersion) == latest {
            return .nothing
        }
        guard isFirstAnsweredCheck, !promptedVersions.contains(latest) else { return .indicate }
        return .prompt
    }

    /// The version the menu bar and the sidebar point at, if any. Hidden once
    /// skipped, and once installed (the quit that finishes it was cancelled,
    /// and the Updates pane says what's left to do).
    static func indicatedVersion(
        available: String?,
        running: String,
        skippedVersion: String?,
        isInstalled: Bool
    ) -> String? {
        guard let available, !isInstalled else { return nil }
        let offer = offer(
            latest: available,
            running: running,
            skippedVersion: skippedVersion,
            promptedVersions: [],
            isFirstAnsweredCheck: false
        )
        return offer == .nothing ? nil : UpdateEligibility.stripV(available)
    }
}
