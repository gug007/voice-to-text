import Foundation

struct GitHubLatestReleaseLocatorHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String
) throws {
    if actual != expected {
        throw GitHubLatestReleaseLocatorHarnessFailure(
            description: "\(message): expected \(expected), got \(actual)"
        )
    }
}

@main
struct GitHubLatestReleaseLocatorHarness {
    static func main() throws {
        try usesGitHubWebLatestReleaseURL()
        try extractsTagFromLatestReleaseRedirect()
        try rejectsOtherRepositories()
        try buildsVersionedAssetDownloadURL()
        print("GitHub latest release locator harness passed")
    }

    private static func usesGitHubWebLatestReleaseURL() throws {
        try expect(
            GitHubLatestReleaseLocator.latestReleaseURL(repo: "gug007/voice-to-text"),
            URL(string: "https://github.com/gug007/voice-to-text/releases/latest")!,
            "latest release lookup does not use api.github.com"
        )
    }

    private static func extractsTagFromLatestReleaseRedirect() throws {
        let finalURL = URL(string: "https://github.com/gug007/voice-to-text/releases/tag/v0.0.19")!
        try expect(
            GitHubLatestReleaseLocator.tagName(from: finalURL, repo: "gug007/voice-to-text"),
            "v0.0.19",
            "latest release redirect exposes the tag"
        )
    }

    private static func rejectsOtherRepositories() throws {
        let finalURL = URL(string: "https://github.com/other/voice-to-text/releases/tag/v0.0.19")!
        try expect(
            GitHubLatestReleaseLocator.tagName(from: finalURL, repo: "gug007/voice-to-text"),
            nil,
            "locator does not accept redirects for another repository"
        )
    }

    private static func buildsVersionedAssetDownloadURL() throws {
        try expect(
            GitHubLatestReleaseLocator.versionedAssetURL(
                repo: "gug007/voice-to-text",
                tagName: "v0.0.19"
            ),
            URL(string: "https://github.com/gug007/voice-to-text/releases/download/v0.0.19/VoiceToText-0.0.19.dmg")!,
            "locator constructs the versioned DMG download URL"
        )
    }
}
