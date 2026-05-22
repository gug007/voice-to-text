import Foundation

enum GitHubLatestReleaseLocator {
    static func latestReleaseURL(repo: String) -> URL {
        URL(string: "https://github.com/\(repo)/releases/latest")!
    }

    static func tagName(from finalURL: URL, repo: String) -> String? {
        guard finalURL.host == "github.com" else { return nil }

        let repoParts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard repoParts.count == 2 else { return nil }

        let pathParts = finalURL.pathComponents.filter { $0 != "/" }
        guard pathParts.count >= 5,
              pathParts[0] == repoParts[0],
              pathParts[1] == repoParts[1],
              pathParts[2] == "releases",
              pathParts[3] == "tag",
              !pathParts[4].isEmpty else {
            return nil
        }

        return pathParts[4]
    }

    static func versionedAssetName(tagName: String) -> String {
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        return "VoiceToText-\(version).dmg"
    }

    static func versionedAssetURL(repo: String, tagName: String) -> URL {
        URL(
            string: "https://github.com/\(repo)/releases/download/\(tagName)/\(versionedAssetName(tagName: tagName))"
        )!
    }
}
