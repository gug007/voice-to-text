import AppKit
import Foundation
import Observation
import OSLog
import Security

@Observable
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(latestVersion: String, assetURL: URL, notes: String)
        case downloading(fraction: Double)
        case installing
        case error(String)
    }

    private(set) var status: Status = .idle

    var currentVersion: String { Self.runningVersion }

    private nonisolated static var runningVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    private nonisolated static let repo = "gug007/voice-to-text"
    /// Where every failed or refused install sends the user: the latest
    /// release's page, to download the DMG and install it by hand.
    nonisolated static let releasesPageURL = URL(string: "https://github.com/\(repo)/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60  // 24h
    private static let skippedVersionKey = "updater.skippedVersion"

    private init() {}

    /// Background auto-check loop. Runs once on start (and prompts the user
    /// if an update is available) then checks again every 24h.
    /// No-op in Debug builds so local runs don't thrash the GitHub API.
    func autoCheckLoop() async {
        #if DEBUG
        return
        #else
        var isFirstCheck = true
        while !Task.isCancelled {
            _ = try? await checkForUpdate(silent: true)
            if isFirstCheck {
                isFirstCheck = false
                await promptForAvailableUpdateIfNeeded()
            }
            try? await Task.sleep(for: .seconds(Self.checkInterval))
        }
        #endif
    }

    // MARK: - Launch prompt

    private func promptForAvailableUpdateIfNeeded() async {
        guard case .available(let latest, _, let notes) = status,
              !isVersionSkipped(latest) else {
            return
        }

        switch presentUpdateAlert(latestVersion: latest, notes: notes) {
        case .install:
            await installUpdate()
            // Unlike the Updates pane, the prompt has nowhere to show a failure,
            // and an install that ends without a relaunch would look ignored.
            if case .error(let message) = status {
                presentInstallFailureAlert(message)
            }
        case .skip:
            skipVersion(latest)
        case .later:
            break
        }
    }

    private enum PromptResponse { case install, later, skip }

    private func presentUpdateAlert(latestVersion: String, notes: String) -> PromptResponse {
        let alert = NSAlert()
        alert.messageText = "VoiceToText \(latestVersion) is available"
        alert.informativeText = Self.promptBody(currentVersion: currentVersion, notes: notes)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .install
        case .alertThirdButtonReturn: return .skip
        default: return .later
        }
    }

    private func presentInstallFailureAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "The update wasn't installed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Download Manually")
        alert.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.releasesPageURL)
        }
    }

    private func isVersionSkipped(_ version: String) -> Bool {
        UserDefaults.standard.string(forKey: Self.skippedVersionKey) == version
    }

    private func skipVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: Self.skippedVersionKey)
    }

    /// NSAlert's informativeText wraps but isn't scrollable, so long release
    /// notes get truncated visually. Preview-cap here and let the Updates
    /// pane show the full text.
    private static func promptBody(currentVersion: String, notes: String) -> String {
        let header = "You're running \(currentVersion)."
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return header }
        let previewLimit = 400
        let preview = trimmed.count > previewLimit
            ? trimmed.prefix(previewLimit).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            : trimmed
        return "\(header)\n\n\(preview)"
    }

    /// - Parameter silent: When true (background checks), failures reset status
    ///   to `.idle` instead of surfacing `.error` to the Updates pane.
    @discardableResult
    func checkForUpdate(silent: Bool = false) async throws -> Bool {
        status = .checking
        do {
            let release = try await fetchLatestRelease()
            let latest = UpdateEligibility.stripV(release.tagName)
            let current = UpdateEligibility.stripV(currentVersion)
            guard UpdateEligibility.isNewer(latest: latest, current: current) else {
                status = .upToDate
                return false
            }
            guard let asset = release.assets.first(where: { asset in
                asset.name.hasPrefix("VoiceToText-") && asset.name.hasSuffix(".dmg")
            }) else {
                status = silent ? .idle : .error("Release v\(latest) has no DMG asset")
                return false
            }
            status = .available(
                latestVersion: latest,
                assetURL: asset.browserDownloadURL,
                notes: release.body ?? ""
            )
            return true
        } catch {
            status = silent ? .idle : .error(error.localizedDescription)
            throw error
        }
    }

    func installUpdate() async {
        guard case .available(_, let url, _) = status else { return }
        // performInstall enforces this before the swap; checking here as well
        // saves a download that could never be installed.
        guard CodeSigning.runningDesignatedRequirement() != nil else {
            status = .error(Self.withManualDownloadHint(UpdaterError.unverifiableBuild.localizedDescription))
            return
        }
        do {
            status = .downloading(fraction: 0)
            let dmgURL = try await downloadDMG(from: url) { [weak self] pct in
                Task { @MainActor in
                    self?.status = .downloading(fraction: pct)
                }
            }
            status = .installing
            // performInstall blocks on hdiutil/ditto — keep it off the main actor.
            try await Task.detached { try Self.performInstall(dmgURL: dmgURL) }.value
            // performInstall terminates the process; we never get here on success.
        } catch {
            AppLog.dictation.error("Update install failed: \(error.localizedDescription)")
            status = .error(Self.withManualDownloadHint(error.localizedDescription))
        }
    }

    /// A failed install can leave someone stuck on this version, so every
    /// failure says how to get the new one without the updater.
    private static func withManualDownloadHint(_ message: String) -> String {
        "\(message) Download the latest version from \(releasesPageURL.absoluteString) instead."
    }

    // MARK: - GitHub API

    private struct Release: Decodable {
        let tagName: String
        let body: String?
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdaterError.network("Invalid response")
        }
        guard http.statusCode == 200 else {
            throw UpdaterError.network("GitHub API returned status \(http.statusCode)")
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // MARK: - Download

    private func downloadDMG(
        from url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let delegate = DownloadDelegate(progress: progress) { result in
                cont.resume(with: result)
            }
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 600
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    // MARK: - Install

    private nonisolated static func performInstall(dmgURL: URL) throws {
        // Always the running bundle's own path: never a name taken from the DMG,
        // which could install a second copy elsewhere and launch that instead.
        let appPath = Bundle.main.bundlePath
        let fm = FileManager.default

        // If Gatekeeper is running the app from a randomized read-only translocation
        // location (first-launch-from-DMG path), we can't overwrite the bundle in place.
        // Fail fast with a message the user can actually act on.
        if appPath.contains("/AppTranslocation/") {
            throw UpdaterError.install(
                "VoiceToText is running from a read-only location. Move it to /Applications and relaunch, then try updating again."
            )
        }

        guard let requirement = CodeSigning.runningDesignatedRequirement() else {
            throw UpdaterError.unverifiableBuild
        }

        let mountPoint = fm.temporaryDirectory
            .appendingPathComponent("vtt-mount-\(UUID().uuidString)")
        try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        defer {
            _ = try? Self.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
            try? fm.removeItem(at: mountPoint)
            try? fm.removeItem(at: dmgURL)
        }

        // Mount the DMG
        try Self.run("/usr/bin/hdiutil", [
            "attach", dmgURL.path,
            "-nobrowse",
            "-mountpoint", mountPoint.path
        ])

        // Find the .app inside the mounted volume
        let contents = try fm.contentsOfDirectory(atPath: mountPoint.path)
        guard let newAppName = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdaterError.install("No .app found inside the DMG")
        }

        let srcApp = mountPoint.appendingPathComponent(newAppName)
        let stagingApp = appPath + ".new"
        let stagingURL = URL(fileURLWithPath: stagingApp)

        // Ditto new app into staging path next to the current bundle
        if fm.fileExists(atPath: stagingApp) {
            try fm.removeItem(atPath: stagingApp)
        }
        try Self.run("/usr/bin/ditto", [srcApp.path, stagingApp])

        // Verify the staged copy, the exact bytes the swap installs, and never
        // leave a rejected bundle behind beside the app.
        do {
            try verifyStagedApp(at: stagingURL, requirement: requirement)
        } catch {
            try? fm.removeItem(at: stagingURL)
            throw error
        }

        // Atomic swap: replaceItemAt renames staging over the old bundle in one step,
        // so a crash mid-swap can't leave us without a working app.
        _ = try fm.replaceItemAt(URL(fileURLWithPath: appPath), withItemAt: stagingURL)

        // Eagerly detach before we exit (defer runs after relaunch script spawns,
        // but the script sleeps waiting for our PID to exit so it won't race).
        _ = try? Self.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])

        // Spawn a detached bash process that waits for this PID to exit,
        // then launches the updated bundle. Child survives parent death
        // because it's re-parented to launchd when the parent terminates.
        // The pid and path arrive as positional arguments ($1, $2), so a path
        // with quotes or `$` in it can't change what the script runs.
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let script = #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; sleep 0.5; /usr/bin/open "$2""#
        let relaunch = Process()
        relaunch.launchPath = "/bin/bash"
        relaunch.arguments = ["-c", script, "vtt-relaunch", pid, appPath]
        relaunch.standardInput = FileHandle.nullDevice
        relaunch.standardOutput = FileHandle.nullDevice
        relaunch.standardError = FileHandle.nullDevice
        try relaunch.run()

        // Give the relaunch helper a moment to start before we die.
        Thread.sleep(forTimeInterval: 0.3)

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    /// Refuses the staged bundle unless it is this app (same bundle ID), a newer
    /// version, and intact and signed to satisfy the running build's own
    /// designated requirement: same identifier, same Developer ID team. Anyone
    /// able to swap a release asset, but without the signing key, gets stopped
    /// here, and so does a genuine older release.
    private nonisolated static func verifyStagedApp(at url: URL, requirement: SecRequirement) throws {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: infoURL) as? [String: Any]
        let verdict = UpdateEligibility.verdict(
            candidateBundleID: info?["CFBundleIdentifier"] as? String,
            candidateVersion: info?["CFBundleShortVersionString"] as? String,
            runningBundleID: Bundle.main.bundleIdentifier,
            runningVersion: runningVersion
        )
        switch verdict {
        case .eligible:
            break
        case .differentApp(let candidate, let running):
            throw UpdaterError.install(
                "The downloaded update is for “\(candidate ?? "an unknown app")”, not this app (“\(running ?? "unknown")”), so it wasn't installed."
            )
        case .notNewer(let candidate, let running):
            throw UpdaterError.install(
                "The downloaded update (version \(candidate ?? "unknown")) isn't newer than this one (\(running)), so it wasn't installed."
            )
        }

        if let failure = CodeSigning.validationFailure(ofBundleAt: url, against: requirement) {
            AppLog.app.error("Update signature check failed: \(failure, privacy: .public)")
            throw UpdaterError.install(
                "The downloaded update isn't signed by the VoiceToText developer, so it wasn't installed."
            )
        }
    }

    // MARK: - Subprocess helper

    @discardableResult
    private nonisolated static func run(_ tool: String, _ args: [String]) throws -> String {
        let process = Process()
        process.launchPath = tool
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw UpdaterError.install(
                "\(tool) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        return output
    }

    // MARK: - Errors

    enum UpdaterError: LocalizedError {
        case network(String)
        case install(String)
        /// The running build has no Developer ID signature to hold an update
        /// to (an ad-hoc or unsigned local build), so nothing can be verified.
        case unverifiableBuild

        var errorDescription: String? {
            switch self {
            case .network(let msg): return msg
            case .install(let msg): return msg
            case .unverifiableBuild:
                return "This build of VoiceToText isn't signed with a Developer ID, so it can't verify an update and won't install one automatically."
            }
        }
    }
}

// MARK: - Download delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (Double) -> Void
    private let completionHandler: @Sendable (Result<URL, Error>) -> Void
    private let lock = NSLock()
    private var finished = false
    // Strong ref so we can invalidate. URLSession also retains its delegate,
    // so we must break this cycle via finishTasksAndInvalidate() on completion.
    var session: URLSession?

    init(
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.progressHandler = progress
        self.completionHandler = completion
    }

    private func finishOnce(_ result: Result<URL, Error>) {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        let sess = session
        session = nil
        lock.unlock()
        guard !alreadyFinished else { return }
        sess?.finishTasksAndInvalidate()
        completionHandler(result)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(pct)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // An error page (a 404 for a missing asset, a rate-limit page) still
        // "finishes downloading"; only a 200 is the DMG.
        guard let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (downloadTask.response as? HTTPURLResponse)?.statusCode
            finishOnce(.failure(AppUpdater.UpdaterError.network(
                "The update download failed (HTTP \(code.map(String.init) ?? "no response"))."
            )))
            return
        }
        // URLSession deletes `location` as soon as this method returns,
        // so move the file to a stable temp path before we leave.
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtt-update-\(UUID().uuidString).dmg")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            finishOnce(.success(dest))
        } catch {
            finishOnce(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finishOnce(.failure(error))
        }
        // Success path is handled in didFinishDownloadingTo.
    }
}
