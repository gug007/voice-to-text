import Foundation

struct UpdateEligibilityHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw UpdateEligibilityHarnessFailure(description: message)
    }
}

private let release = "voice-to-text-ai.VoiceToText"
private let dev = "voice-to-text-ai.VoiceToText.dev"

private func verdict(
    _ candidateID: String?,
    _ candidateVersion: String?,
    running runningID: String? = release,
    _ runningVersion: String = "0.1.0"
) -> UpdateEligibility.Verdict {
    UpdateEligibility.verdict(
        candidateBundleID: candidateID,
        candidateVersion: candidateVersion,
        runningBundleID: runningID,
        runningVersion: runningVersion
    )
}

@main
struct UpdateEligibilityHarness {
    static func main() throws {
        try comparesVersions()
        try stripsTagPrefix()
        try acceptsSameAppNewerVersion()
        try rejectsOtherApps()
        try rejectsDowngradesAndReinstalls()
        print("Update eligibility harness passed")
    }

    private static func comparesVersions() throws {
        let newer = UpdateEligibility.isNewer
        try expect(newer("0.0.58", "0.0.57"), "patch bump is newer")
        try expect(newer("0.1.0", "0.0.99"), "minor bump beats a higher patch")
        try expect(newer("1.0.0", "0.9.9"), "major bump is newer")
        try expect(newer("0.0.10", "0.0.9"), "components compare numerically, not as text")
        try expect(!newer("0.1.0", "0.1.0"), "same version is not newer")
        try expect(!newer("0.0.57", "0.0.58"), "older is not newer")
        try expect(!newer("0.1", "0.1.0"), "missing components count as zero")
        try expect(newer("0.2", "0.1.9"), "short versions still compare")
        try expect(!newer("0.1.0-beta.1", "0.1.0"), "a prerelease suffix is ignored")
        try expect(!newer("garbage", "0.0.1"), "an unreadable version is never newer")
        try expect(!newer("", "0.0.0"), "an empty version is never newer")
    }

    private static func stripsTagPrefix() throws {
        try expect(UpdateEligibility.stripV("v0.1.2") == "0.1.2", "tag prefix dropped")
        try expect(UpdateEligibility.stripV("0.1.2") == "0.1.2", "bare version kept")
    }

    private static func acceptsSameAppNewerVersion() throws {
        try expect(verdict(release, "0.1.1") == .eligible, "same app, newer patch")
        try expect(verdict(release, "0.2.0") == .eligible, "same app, newer minor")
        try expect(verdict(release, "v0.1.1") == .eligible, "a v-prefixed bundle version still compares")
    }

    private static func rejectsOtherApps() throws {
        try expect(
            verdict(dev, "0.2.0") == .differentApp(candidate: dev, running: release),
            "the Dev variant never replaces the release"
        )
        try expect(
            verdict(release, "0.2.0", running: dev) == .differentApp(candidate: release, running: dev),
            "the release never replaces the Dev variant"
        )
        try expect(
            verdict("com.example.Other", "9.9.9") == .differentApp(candidate: "com.example.Other", running: release),
            "an unrelated app is refused however new"
        )
        try expect(
            verdict(nil, "0.2.0") == .differentApp(candidate: nil, running: release),
            "a bundle without an identifier is refused"
        )
        try expect(
            verdict(release, "0.2.0", running: nil) == .differentApp(candidate: release, running: nil),
            "a running build without an identifier accepts nothing"
        )
        try expect(
            verdict("", "0.2.0", running: "") == .differentApp(candidate: "", running: ""),
            "two empty identifiers are not a match"
        )
        try expect(
            verdict("VOICE-TO-TEXT-AI.VOICETOTEXT", "0.2.0") != .eligible,
            "identifiers compare exactly"
        )
    }

    private static func rejectsDowngradesAndReinstalls() throws {
        try expect(
            verdict(release, "0.0.58") == .notNewer(candidate: "0.0.58", running: "0.1.0"),
            "a downgrade is refused"
        )
        try expect(
            verdict(release, "0.1.0") == .notNewer(candidate: "0.1.0", running: "0.1.0"),
            "the same version is refused"
        )
        try expect(
            verdict(release, nil) == .notNewer(candidate: nil, running: "0.1.0"),
            "a bundle without a version is refused"
        )
        try expect(
            verdict(release, "not-a-version") == .notNewer(candidate: "not-a-version", running: "0.1.0"),
            "an unreadable version is refused"
        )
    }
}
