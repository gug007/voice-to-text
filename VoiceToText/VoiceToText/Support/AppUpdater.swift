import AppKit
import Foundation
import Network
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
    private static let skippedVersionKey = "updater.skippedVersion"

    /// The newest release the last answered check found, while it's newer
    /// than this build. Kept apart from `status` so an install that fails, or
    /// a background check that can't get through, doesn't hide it.
    private(set) var availableVersion: String?

    /// The version "Skip This Version" was pressed for. Mirrored from
    /// UserDefaults so the indicators drop it the moment it's skipped.
    private(set) var skippedVersion: String?

    /// The update the menu bar item and the sidebar badge point at, or nil
    /// when there's nothing to point at.
    var indicatedVersion: String? {
        var isInstalled = false
        if case .installed = status { isInstalled = true }
        return UpdateCheckPolicy.indicatedVersion(
            available: availableVersion,
            running: currentVersion,
            skippedVersion: skippedVersion,
            isInstalled: isInstalled
        )
    }

    /// Versions the modal prompt has already been shown for this session.
    @ObservationIgnored private var promptedVersions: Set<String> = []
    /// Whether any check this session has had an answer from GitHub. Only
    /// the first answer may prompt.
    @ObservationIgnored private var hasAnsweredCheck = false
    @ObservationIgnored private var lastFailure: UpdateCheckPolicy.Failure?
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var notBefore: Date?
    @ObservationIgnored private var lastAttemptAt: Date?
    /// The wait before the next background check, cancelled to check early
    /// when the network comes back.
    @ObservationIgnored private var pendingSleep: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?

    private init() {
        skippedVersion = UserDefaults.standard.string(forKey: Self.skippedVersionKey)
    }

    /// Background auto-check loop. Checks once on start, then on the cadence
    /// `UpdateCheckPolicy` sets: a short backoff after a failure, every 24h
    /// otherwise, and early when the network returns after a failure.
    /// No-op in Debug builds so local runs don't thrash the GitHub API.
    func autoCheckLoop() async {
        // A crash or a failure mid-install can leave a staging copy or the old
        // bundle's backup beside the app; this runs once per launch.
        await Task.detached(priority: .utility) { Self.removeInstallLeftovers() }.value
        #if DEBUG
        return
        #else
        startNetworkMonitor()
        while !Task.isCancelled {
            let isFirstAnsweredCheck = !hasAnsweredCheck
            if await checkForUpdate(silent: true) == .answered {
                await offerAvailableUpdate(isFirstAnsweredCheck: isFirstAnsweredCheck)
            }
            let delay = UpdateCheckPolicy.nextCheckDelay(
                after: lastFailure,
                consecutiveFailures: consecutiveFailures
            )
            await sleepUntilNextCheck(delay)
        }
        #endif
    }

    private func sleepUntilNextCheck(_ delay: TimeInterval) async {
        let sleeper = Task<Void, Never> { try? await Task.sleep(for: .seconds(delay)) }
        pendingSleep = sleeper
        await withTaskCancellationHandler {
            await sleeper.value
        } onCancel: {
            sleeper.cancel()
        }
        pendingSleep = nil
    }

    // MARK: - Network

    private func startNetworkMonitor() {
        guard pathMonitor == nil else { return }
        pathMonitor = Self.makePathMonitor()
    }

    /// Built outside the main actor: the handler runs on the monitor's queue,
    /// where a closure inferred as main-actor isolated would trap.
    private nonisolated static func makePathMonitor() -> NWPathMonitor {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in AppUpdater.shared.networkBecameAvailable() }
        }
        monitor.start(queue: DispatchQueue(label: "voice-to-text-ai.VoiceToText.updater.network", qos: .utility))
        return monitor
    }

    /// A check that failed for want of a connection shouldn't wait out its
    /// backoff (up to a day) once there is one again.
    private func networkBecameAvailable() {
        guard let pendingSleep,
              UpdateCheckPolicy.shouldCheckWhenNetworkReturns(
                  lastFailure: lastFailure,
                  notBefore: notBefore,
                  lastAttemptAt: lastAttemptAt,
                  now: Date()
              ) else { return }
        AppLog.app.notice("Network is back; checking for updates now")
        pendingSleep.cancel()
    }

    // MARK: - Prompt

    /// Shows the modal for an update a background check just found, when the
    /// policy says this is the moment: the session's first answered check,
    /// once per version. Everything else is left to the indicators.
    private func offerAvailableUpdate(isFirstAnsweredCheck: Bool) async {
        guard case .available(let latest, _, _) = status else { return }
        let offer = UpdateCheckPolicy.offer(
            latest: latest,
            running: currentVersion,
            skippedVersion: skippedVersion,
            promptedVersions: promptedVersions,
            isFirstAnsweredCheck: isFirstAnsweredCheck
        )
        guard offer == .prompt else { return }

        // A retry of the launch check can land mid-dictation or mid-meeting,
        // where a modal would steal focus from the text field or the call —
        // or sit over a HUD card the user still has to act on.
        var notes = ""
        repeat {
            await waitUntilUserIsFree()
            // Installed, skipped or superseded from the Updates pane meanwhile.
            guard case .available(let current, _, let currentNotes) = status,
                  current == latest, skippedVersion != latest, !Task.isCancelled else {
                return
            }
            notes = currentNotes
            // Looked at again in the same main-actor turn as the alert, so
            // nothing that took the HUD after the wait can end up under it.
        } while isUserBusy
        promptedVersions.insert(latest)

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

    private func waitUntilUserIsFree() async {
        while isUserBusy, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
        }
    }

    /// Recording, transcribing, reviewing — or idle with a card still up that
    /// the alert would block: a discard's Undo, whose window runs out under a
    /// modal and takes the audio with it, or a failure card's Retry.
    private var isUserBusy: Bool {
        if MeetingController.shared.isBusy { return true }
        if DictationController.shared.isHoldingUserAttention { return true }
        switch DictationController.shared.state {
        case .idle, .error: return false
        case .preparing, .recording, .transcribing, .reviewing, .delivering: return true
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

    private func skipVersion(_ version: String) {
        skippedVersion = version
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

    // MARK: - Check

    enum CheckOutcome: Equatable {
        /// GitHub answered: up to date, or an update is available.
        case answered
        case failed
        /// Not run: another check, a download or an install is under way, or
        /// the update is already installed.
        case skipped
    }

    /// - Parameter silent: When true (background checks), a failure leaves
    ///   the status as it was instead of surfacing `.error` to the Updates
    ///   pane, so an update found earlier stays on offer.
    @discardableResult
    func checkForUpdate(silent: Bool = false) async -> CheckOutcome {
        switch status {
        case .installed:
            // The running version predates the one already on disk, so a check
            // would offer it again.
            return .skipped
        case .checking, .downloading, .installing:
            // A check now would overwrite the progress the pane is showing.
            return .skipped
        case .idle, .upToDate, .available, .error:
            break
        }
        let previous = status
        status = .checking
        lastAttemptAt = Date()
        do {
            let release = try await fetchLatestRelease()
            let latest = UpdateEligibility.stripV(release.tagName)
            let current = UpdateEligibility.stripV(currentVersion)
            guard UpdateEligibility.isNewer(latest: latest, current: current) else {
                recordAnswer()
                availableVersion = nil
                status = .upToDate
                return .answered
            }
            guard let asset = release.assets.first(where: { asset in
                asset.name.hasPrefix("VoiceToText-") && asset.name.hasSuffix(".dmg")
            }) else {
                throw UpdaterError.missingAsset(version: latest)
            }
            recordAnswer()
            availableVersion = latest
            status = .available(
                latestVersion: latest,
                assetURL: asset.browserDownloadURL,
                notes: release.body ?? ""
            )
            return .answered
        } catch {
            recordFailure(Self.checkFailure(for: error))
            AppLog.app.notice("Update check failed (\(self.consecutiveFailures, privacy: .public) in a row): \(error.localizedDescription, privacy: .public)")
            status = silent ? previous : .error(error.localizedDescription)
            return .failed
        }
    }

    private func recordAnswer() {
        hasAnsweredCheck = true
        lastFailure = nil
        consecutiveFailures = 0
        notBefore = nil
    }

    private func recordFailure(_ failure: UpdateCheckPolicy.Failure) {
        lastFailure = failure
        consecutiveFailures += 1
        notBefore = UpdateCheckPolicy.notBefore(after: failure, now: Date())
    }

    private static func checkFailure(for error: Error) -> UpdateCheckPolicy.Failure {
        switch error as? UpdaterError {
        case .httpStatus(let code, let retryAfter):
            return UpdateCheckPolicy.failure(forHTTPStatus: code, retryAfter: retryAfter)
        case .missingAsset:
            // Most likely published moments before its DMG finished uploading.
            return .transient
        case .network, .install, .unverifiableBuild, nil:
            return UpdateCheckPolicy.failure(for: error)
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
            throw UpdaterError.httpStatus(
                http.statusCode,
                retryAfter: UpdateCheckPolicy.retryAfter(
                    retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After"),
                    rateLimitRemaining: http.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
                    rateLimitReset: http.value(forHTTPHeaderField: "X-RateLimit-Reset"),
                    now: Date()
                )
            )
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
        /// The release feed answered with something other than 200.
        /// `retryAfter` is the wait GitHub asked for, when it said.
        case httpStatus(Int, retryAfter: TimeInterval?)
        /// The latest release has no DMG to install, at least not yet.
        case missingAsset(version: String)
        case install(String)
        /// The running build has no Developer ID signature to hold an update
        /// to (an ad-hoc or unsigned local build), so nothing can be verified.
        case unverifiableBuild

        var errorDescription: String? {
            switch self {
            case .network(let msg): return msg
            case .httpStatus(403, _), .httpStatus(429, _):
                return "GitHub is limiting update checks from this network for now. VoiceToText will try again on its own."
            case .httpStatus(let code, _): return "GitHub API returned status \(code)"
            case .missingAsset(let version): return "Release v\(version) has no DMG asset"
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
