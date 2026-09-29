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
        /// The new version is on disk but the quit that should have relaunched
        /// into it was cancelled. `relaunches` says whether the helper that
        /// reopens the app on quit is waiting.
        case installed(relaunches: Bool)
        case error(String)
    }

    private(set) var status: Status = .idle

    /// True from the moment the verified update is swapped in until the app
    /// quits (or the quit is cancelled). A conversation mustn't start then:
    /// the quit would cut it off, and the bundle on disk is already the new one.
    private(set) var isFinishingInstall = false

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
        // A crash or a failure mid-install can leave a staging copy or the old
        // bundle's backup beside the app; this runs once per launch.
        await Task.detached(priority: .utility) { Self.removeInstallLeftovers() }.value
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
        // The running version predates the one already on disk, so a check
        // would offer it again.
        if case .installed = status { return false }
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
        guard case .available(let version, let url, _) = status else { return }
        let available = status
        guard !conversationBlocksInstall() else { return }
        // stageUpdate enforces this before anything is copied; checking here as
        // well saves a download that could never be installed.
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
            // A conversation started while the update downloaded. The Updates
            // pane already says why Install is unavailable; an alert here would
            // steal focus in the middle of the meeting.
            if MeetingController.shared.isBusy {
                try? FileManager.default.removeItem(at: dmgURL)
                status = available
                return
            }
            status = .installing
            // Mounting, copying and verifying block on hdiutil/ditto — keep them
            // off the main actor.
            let staged = try await Task.detached { try Self.stageUpdate(dmgURL: dmgURL) }.value
            try finishInstall(staged: staged, version: version, available: available)
        } catch {
            AppLog.dictation.error("Update install failed: \(error.localizedDescription)")
            status = .error(Self.withManualDownloadHint(error.localizedDescription))
        }
    }

    /// Swaps the verified update in and quits, in one main-actor turn, so no
    /// conversation can start between the busy check and the quit: one that
    /// did would face a quit prompt with the old bundle already replaced.
    /// On success the process exits; returning means the swap was called off
    /// or the quit was cancelled.
    private func finishInstall(staged: URL, version: String, available: Status) throws {
        guard !MeetingController.shared.isBusy else {
            // Started while the update was being copied and checked. Keep the
            // running app as it is; the update stays available.
            try? FileManager.default.removeItem(at: staged)
            status = available
            return
        }
        isFinishingInstall = true
        do {
            try Self.swapIn(staged: staged)
        } catch {
            isFinishingInstall = false
            throw error
        }
        let relaunches = Self.armRelaunch()
        if !relaunches {
            // Installed all the same; it just can't reopen itself.
            let alert = NSAlert()
            alert.messageText = "VoiceToText \(version) is installed"
            alert.informativeText = "VoiceToText couldn't reopen itself after the update. It quits now; open it again from your Applications folder."
            alert.addButton(withTitle: "Quit")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        NSApp.terminate(nil)
        // Only reached when the quit was cancelled.
        isFinishingInstall = false
        status = .installed(relaunches: relaunches)
    }

    /// Installing quits and relaunches the app, which would cut off a
    /// conversation that is recording or transcribing, so it's refused with a
    /// word of why. Refused rather than deferred: an app that quits by itself
    /// the moment a meeting ends would be the worse surprise. The update stays
    /// available. Returns true when the install must not go ahead.
    private func conversationBlocksInstall() -> Bool {
        guard MeetingController.shared.isBusy else { return false }
        let alert = NSAlert()
        alert.messageText = "Finish the conversation first"
        alert.informativeText = "Installing the update quits and relaunches VoiceToText, which would cut off the conversation that's recording or transcribing. Install it from Settings → Updates once the conversation is saved."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        return true
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

    /// Beside the running bundle, on the same volume so the swap is a rename.
    private nonisolated static var stagingURL: URL {
        Bundle.main.bundleURL.appendingPathExtension("new")
    }

    /// Where the swap keeps the old bundle until the new one passes its check.
    private nonisolated static var backupURL: URL {
        Bundle.main.bundleURL.appendingPathExtension("old")
    }

    /// Mounts the DMG, copies its app beside the running one and verifies the
    /// copy. Returns the verified staging copy; leaves nothing behind (mount,
    /// DMG, partial or rejected copy) when it throws.
    private nonisolated static func stageUpdate(dmgURL: URL) throws -> URL {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: dmgURL) }

        // If Gatekeeper is running the app from a randomized read-only translocation
        // location (first-launch-from-DMG path), we can't overwrite the bundle in place.
        // Fail fast with a message the user can actually act on.
        if Bundle.main.bundlePath.contains("/AppTranslocation/") {
            throw UpdaterError.install(
                "VoiceToText is running from a read-only location. Move it to /Applications and relaunch, then try updating again."
            )
        }

        guard let requirement = CodeSigning.runningDesignatedRequirement(),
              let team = CodeSigning.runningTeamIdentifier else {
            throw UpdaterError.unverifiableBuild
        }

        let mountPoint = fm.temporaryDirectory
            .appendingPathComponent("vtt-mount-\(UUID().uuidString)")
        try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        defer {
            _ = try? Self.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
            try? fm.removeItem(at: mountPoint)
        }

        // Mount the DMG
        try Self.run("/usr/bin/hdiutil", [
            "attach", dmgURL.path,
            "-nobrowse",
            "-mountpoint", mountPoint.path
        ])

        // Find the .app inside the mounted volume. Its name doesn't matter: the
        // update always goes over the running bundle's own path, never a name
        // taken from the DMG, which could install a second copy elsewhere.
        let contents = try fm.contentsOfDirectory(atPath: mountPoint.path)
        guard let newAppName = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdaterError.install("No .app found inside the DMG")
        }

        let srcApp = mountPoint.appendingPathComponent(newAppName)
        let staging = stagingURL
        try? fm.removeItem(at: staging)
        do {
            try Self.run("/usr/bin/ditto", [srcApp.path, staging.path])
            // Verify the copy, the exact bytes the swap installs.
            try verifyUpdate(at: staging, requirement: requirement, team: team)
        } catch {
            // A partial copy or a rejected bundle never stays beside the app.
            try? fm.removeItem(at: staging)
            throw error
        }
        return staging
    }

    /// Swaps the verified staging copy in over the running bundle, keeping the
    /// old one as a backup until the installed bundle passes the check again:
    /// the copy sat in a user-writable folder after its check, and
    /// `replaceItemAt` moves whatever is at that path by then. A failure puts
    /// the old bundle back.
    private nonisolated static func swapIn(staged: URL) throws {
        let fm = FileManager.default
        let appURL = Bundle.main.bundleURL
        let backup = backupURL
        guard let requirement = CodeSigning.runningDesignatedRequirement(),
              let team = CodeSigning.runningTeamIdentifier else {
            try? fm.removeItem(at: staged)
            throw UpdaterError.unverifiableBuild
        }

        do {
            _ = try fm.replaceItemAt(
                appURL,
                withItemAt: staged,
                backupItemName: backup.lastPathComponent,
                options: .withoutDeletingBackupItem
            )
        } catch {
            try? fm.removeItem(at: staged)
            // Should the swap have failed halfway, never leave the app missing.
            if !fm.fileExists(atPath: appURL.path), fm.fileExists(atPath: backup.path) {
                try? fm.moveItem(at: backup, to: appURL)
            }
            throw error
        }

        do {
            try verifyUpdate(at: appURL, requirement: requirement, team: team)
        } catch {
            do {
                _ = try fm.replaceItemAt(appURL, withItemAt: backup)
            } catch {
                AppLog.app.fault("Couldn't restore the previous app after the installed update failed its check: \(error.localizedDescription, privacy: .public)")
                throw UpdaterError.install(
                    "The update failed its final check, and the previous version couldn't be put back. Reinstall VoiceToText by hand."
                )
            }
            throw error
        }
        try? fm.removeItem(at: backup)
    }

    /// Starts a detached helper that waits for this process to exit, then
    /// opens the updated bundle. The child survives our exit because it's
    /// re-parented to launchd. The pid and path arrive as positional arguments
    /// ($1, $2), so a path with quotes or `$` in it can't change what the script
    /// runs. False when the helper couldn't start: the update is installed all
    /// the same, it just won't reopen by itself.
    private nonisolated static func armRelaunch() -> Bool {
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let script = #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; sleep 0.5; /usr/bin/open "$2""#
        let relaunch = Process()
        relaunch.launchPath = "/bin/bash"
        relaunch.arguments = ["-c", script, "vtt-relaunch", pid, Bundle.main.bundlePath]
        relaunch.standardInput = FileHandle.nullDevice
        relaunch.standardOutput = FileHandle.nullDevice
        relaunch.standardError = FileHandle.nullDevice
        do {
            try relaunch.run()
        } catch {
            AppLog.app.error("Couldn't start the relaunch helper: \(error.localizedDescription, privacy: .public)")
            return false
        }
        // Give the relaunch helper a moment to start before we die.
        Thread.sleep(forTimeInterval: 0.3)
        return true
    }

    /// Removes a staging copy or backup left beside the app by an install
    /// that crashed or failed partway. The running bundle is never touched.
    private nonisolated static func removeInstallLeftovers() {
        let fm = FileManager.default
        for leftover in [stagingURL, backupURL] where fm.fileExists(atPath: leftover.path) {
            do {
                try fm.removeItem(at: leftover)
            } catch {
                AppLog.app.error("Couldn't remove update leftover \(leftover.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Refuses a bundle unless it is this app (same bundle ID), a newer
    /// version, intact, and signed to satisfy the running build's designated
    /// requirement (an Apple-issued chain and the same identifier) by the same
    /// team. Anyone able to swap a release asset, but without the signing key,
    /// gets stopped here, and so does a genuine older release.
    private nonisolated static func verifyUpdate(
        at url: URL,
        requirement: SecRequirement,
        team: String
    ) throws {
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

        if let failure = CodeSigning.validationFailure(ofBundleAt: url, against: requirement, teamIdentifier: team) {
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
