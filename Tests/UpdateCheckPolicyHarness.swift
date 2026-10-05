import Foundation

struct UpdateCheckPolicyHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw UpdateCheckPolicyHarnessFailure(description: message)
    }
}

private typealias Policy = UpdateCheckPolicy

private let day: TimeInterval = 24 * 60 * 60
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func offer(
    _ latest: String,
    running: String = "0.0.53",
    skipped: String? = nil,
    prompted: Set<String> = [],
    first: Bool
) -> Policy.Offer {
    Policy.offer(
        latest: latest,
        running: running,
        skippedVersion: skipped,
        promptedVersions: prompted,
        isFirstAnsweredCheck: first
    )
}

@main
struct UpdateCheckPolicyHarness {
    static func main() throws {
        try promptsOnTheFirstAnswerOnly()
        try neverPromptsTwiceForAVersion()
        try skippedVersionsStayQuiet()
        try indicatesUntilInstalledOrSkipped()
        try backsOffAfterFailures()
        try honoursRateLimits()
        try classifiesFailures()
        try readsRateLimitHeaders()
        try retriesWhenTheNetworkReturns()
        print("Update check policy harness passed")
    }

    private static func promptsOnTheFirstAnswerOnly() throws {
        try expect(offer("0.0.59", first: true) == .prompt, "the launch check prompts for a newer version")
        try expect(offer("v0.0.59", first: true) == .prompt, "a v-prefixed tag still prompts")
        try expect(
            offer("0.0.59", first: false) == .indicate,
            "a version found by a later background check waits behind the indicator"
        )
        try expect(offer("0.0.53", first: true) == .nothing, "the running version is never offered")
        try expect(offer("0.0.52", first: true) == .nothing, "an older version is never offered")
        try expect(offer("0.0.53", first: false) == .nothing, "nothing to indicate when up to date")
    }

    private static func neverPromptsTwiceForAVersion() throws {
        try expect(
            offer("0.0.59", prompted: ["0.0.59"], first: true) == .indicate,
            "one modal per version per session"
        )
        try expect(
            offer("0.0.60", prompted: ["0.0.59"], first: true) == .prompt,
            "prompting for one version doesn't silence a newer one on the first answer"
        )
    }

    private static func skippedVersionsStayQuiet() throws {
        try expect(offer("0.0.59", skipped: "0.0.59", first: true) == .nothing, "Skip This Version holds")
        try expect(
            offer("0.0.59", skipped: "0.0.59", first: false) == .nothing,
            "a skipped version isn't indicated either"
        )
        try expect(
            offer("v0.0.59", skipped: "0.0.59", first: true) == .nothing,
            "skip matches across the tag prefix"
        )
        try expect(
            offer("0.0.60", skipped: "0.0.59", first: true) == .prompt,
            "skipping one version doesn't skip the next"
        )
    }

    private static func indicatesUntilInstalledOrSkipped() throws {
        let indicated = { (available: String?, skipped: String?, installed: Bool) in
            Policy.indicatedVersion(
                available: available,
                running: "0.0.53",
                skippedVersion: skipped,
                isInstalled: installed
            )
        }
        try expect(indicated("0.0.59", nil, false) == "0.0.59", "an available update is indicated")
        try expect(indicated("v0.0.59", nil, false) == "0.0.59", "the indicator shows a bare version")
        try expect(indicated(nil, nil, false) == nil, "nothing found, nothing indicated")
        try expect(indicated("0.0.59", "0.0.59", false) == nil, "a skipped version isn't indicated")
        try expect(indicated("0.0.59", nil, true) == nil, "an installed update isn't indicated")
        try expect(indicated("0.0.53", nil, false) == nil, "the running version isn't indicated")
    }

    private static func backsOffAfterFailures() throws {
        let delay = Policy.nextCheckDelay
        try expect(delay(nil, 0) == day, "an answered check waits a day")
        try expect(delay(.offline, 1) == 60, "first failure retries after a minute")
        try expect(delay(.offline, 2) == 5 * 60, "second failure retries after five minutes")
        try expect(delay(.transient, 3) == 30 * 60, "third failure retries after half an hour")
        try expect(delay(.transient, 4) == day, "then the normal cadence")
        try expect(delay(.offline, 40) == day, "a long outage stays on the normal cadence")
        try expect(delay(.offline, 0) == 60, "a miscounted failure still backs off from the start")
        try expect(delay(.permanent, 1) == day, "a permanent failure isn't retried early")
        try expect(delay(.rateLimited(retryAfter: nil), 1) == 60, "a rate limit without a hint backs off")
    }

    private static func honoursRateLimits() throws {
        let delay = Policy.nextCheckDelay
        try expect(
            delay(.rateLimited(retryAfter: 45 * 60), 1) == 45 * 60,
            "never sooner than GitHub asked"
        )
        try expect(
            delay(.rateLimited(retryAfter: 10), 2) == 5 * 60,
            "a short hint doesn't shorten the backoff"
        )
        try expect(
            delay(.rateLimited(retryAfter: 3 * day), 1) == day,
            "never later than the normal cadence"
        )
        try expect(
            Policy.notBefore(after: .rateLimited(retryAfter: 600), now: now) == now.addingTimeInterval(600),
            "an announced limit sets the earliest next attempt"
        )
        try expect(
            Policy.notBefore(after: .rateLimited(retryAfter: 3 * day), now: now) == now.addingTimeInterval(day),
            "the earliest next attempt is capped at a day"
        )
        try expect(Policy.notBefore(after: .rateLimited(retryAfter: nil), now: now) == nil, "no hint, no hold")
        try expect(Policy.notBefore(after: .offline, now: now) == nil, "only rate limits hold")
        try expect(Policy.notBefore(after: nil, now: now) == nil, "an answer holds nothing")
    }

    private static func classifiesFailures() throws {
        try expect(
            Policy.failure(forHTTPStatus: 403, retryAfter: 60) == .rateLimited(retryAfter: 60),
            "GitHub's unauthenticated limit answers 403"
        )
        try expect(
            Policy.failure(forHTTPStatus: 429, retryAfter: nil) == .rateLimited(retryAfter: nil),
            "429 is a rate limit"
        )
        try expect(Policy.failure(forHTTPStatus: 502, retryAfter: nil) == .transient, "a server error is retried")
        try expect(Policy.failure(forHTTPStatus: 503, retryAfter: nil) == .transient, "an outage is retried")
        try expect(Policy.failure(forHTTPStatus: 408, retryAfter: nil) == .transient, "a request timeout is retried")
        try expect(Policy.failure(forHTTPStatus: 404, retryAfter: nil) == .permanent, "a missing release isn't")
        try expect(
            Policy.failure(for: URLError(.notConnectedToInternet)) == .offline,
            "no connection at login is offline"
        )
        try expect(Policy.failure(for: URLError(.timedOut)) == .offline, "a timeout counts as offline")
        try expect(Policy.failure(for: URLError(.cannotFindHost)) == .offline, "DNS failure counts as offline")
        try expect(
            Policy.failure(for: URLError(.secureConnectionFailed)) == .transient,
            "other URL errors are retried"
        )
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        try expect(Policy.failure(for: decoding) == .permanent, "an unreadable answer isn't retried early")
        try expect(Policy.failure(for: CocoaError(.fileNoSuchFile)) == .transient, "anything else is retried")
    }

    private static func readsRateLimitHeaders() throws {
        let read = { (retryAfter: String?, remaining: String?, reset: String?) in
            Policy.retryAfter(
                retryAfterHeader: retryAfter,
                rateLimitRemaining: remaining,
                rateLimitReset: reset,
                now: now
            )
        }
        try expect(read("120", nil, nil) == 120, "Retry-After in seconds")
        try expect(read(" 60 ", nil, nil) == 60, "Retry-After tolerates whitespace")
        try expect(read("0", nil, nil) == 0, "Retry-After of zero")
        try expect(read("-5", nil, nil) == nil, "a negative Retry-After is ignored")
        // 1_800_000_000 is Fri, 15 Jan 2027 08:00:00 GMT.
        try expect(read("Fri, 15 Jan 2027 08:10:00 GMT", nil, nil) == 600, "Retry-After as an HTTP date")
        try expect(read("Fri, 15 Jan 2027 07:00:00 GMT", nil, nil) == 0, "a past HTTP date means now")
        try expect(read("soon", nil, nil) == nil, "an unreadable Retry-After is ignored")
        let reset = String(Int(now.timeIntervalSince1970) + 1_800)
        try expect(read(nil, "0", reset) == 1_800, "X-RateLimit-Reset when nothing remains")
        try expect(read(nil, "12", reset) == nil, "X-RateLimit-Reset is ignored while requests remain")
        try expect(read(nil, nil, reset) == nil, "X-RateLimit-Reset needs the remaining count")
        try expect(
            read(nil, "0", String(Int(now.timeIntervalSince1970) - 30)) == 0,
            "a reset in the past means now"
        )
        try expect(read("90", "0", reset) == 90, "Retry-After wins over the reset time")
        try expect(read(nil, nil, nil) == nil, "no headers, no hint")
    }

    private static func retriesWhenTheNetworkReturns() throws {
        let shouldCheck = { (failure: Policy.Failure?, notBefore: Date?, lastAttempt: Date?) in
            Policy.shouldCheckWhenNetworkReturns(
                lastFailure: failure,
                notBefore: notBefore,
                lastAttemptAt: lastAttempt,
                now: now
            )
        }
        let minuteAgo = now.addingTimeInterval(-60)
        try expect(shouldCheck(.offline, nil, minuteAgo), "offline at login, then online: check now")
        try expect(shouldCheck(.transient, nil, minuteAgo), "a dropped request is retried on reconnect")
        try expect(shouldCheck(.offline, nil, nil), "no attempt on record doesn't block a retry")
        try expect(!shouldCheck(nil, nil, minuteAgo), "an answered check waits for its cadence")
        try expect(!shouldCheck(.permanent, nil, minuteAgo), "a permanent failure waits for its cadence")
        try expect(
            !shouldCheck(.rateLimited(retryAfter: 600), now.addingTimeInterval(300), minuteAgo),
            "a reconnect doesn't jump an announced rate limit"
        )
        try expect(
            shouldCheck(.rateLimited(retryAfter: 600), now.addingTimeInterval(-1), minuteAgo),
            "once the limit has passed, a reconnect retries"
        )
        try expect(
            !shouldCheck(.offline, nil, now.addingTimeInterval(-10)),
            "a flapping connection can't trigger back-to-back checks"
        )
    }
}
