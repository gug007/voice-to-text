import AppKit
import Foundation
import Observation
import OSLog

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

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    private static let repo = "gug007/voice-to-text"
    private static let checkInterval: TimeInterval = 24 * 60 * 60  // 24h

    private init() {}

    /// Background auto-check loop. Runs once on start then every 24h.
    /// No-op in Debug builds so local runs don't thrash the GitHub API.
    func autoCheckLoop() async {
        #if DEBUG
        return
        #else
        while !Task.isCancelled {
            _ = try? await checkForUpdate()
            try? await Task.sleep(for: .seconds(Self.checkInterval))
        }
        #endif
    }

    @discardableResult
    func checkForUpdate() async throws -> Bool {
        status = .checking
        do {
            let release = try await fetchLatestRelease()
            let latest = Self.stripV(release.tagName)
            let current = Self.stripV(currentVersion)
            guard Self.isNewer(latest: latest, current: current) else {
                status = .upToDate
                return false
            }
            guard let asset = release.assets.first(where: { asset in
                asset.name.hasPrefix("VoiceToText-") && asset.name.hasSuffix(".dmg")
            }) else {
                status = .error("Release v\(latest) has no DMG asset")
                return false
            }
            status = .available(
                latestVersion: latest,
                assetURL: asset.browserDownloadURL,
                notes: release.body ?? ""
            )
            return true
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func installUpdate() async {
        guard case .available(_, let url, _) = status else { return }
        do {
            status = .downloading(fraction: 0)
            let dmgURL = try await downloadDMG(from: url) { [weak self] pct in
                Task { @MainActor in
                    self?.status = .downloading(fraction: pct)
                }
            }
            status = .installing
            try performInstall(dmgURL: dmgURL)
            // performInstall terminates the process; we never get here on success.
        } catch {
            AppLog.dictation.error("Update install failed: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
        }
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
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    // MARK: - Install

    private nonisolated func performInstall(dmgURL: URL) throws {
        let appPath = Bundle.main.bundlePath
        let fm = FileManager.default

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
        let appDir = (appPath as NSString).deletingLastPathComponent
        let dstApp = (appDir as NSString).appendingPathComponent(newAppName)
        let stagingApp = dstApp + ".new"

        // Ditto new app into staging path next to the current bundle
        if fm.fileExists(atPath: stagingApp) {
            try fm.removeItem(atPath: stagingApp)
        }
        try Self.run("/usr/bin/ditto", [srcApp.path, stagingApp])

        // Remove old, move staging into place
        if fm.fileExists(atPath: dstApp) {
            try fm.removeItem(atPath: dstApp)
        }
        try fm.moveItem(atPath: stagingApp, toPath: dstApp)

        // Eagerly detach before we exit (defer runs after relaunch script spawns,
        // but the script sleeps waiting for our PID to exit so it won't race).
        _ = try? Self.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])

        // Spawn a detached bash process that waits for this PID to exit,
        // then launches the updated bundle. Child survives parent death
        // because it's re-parented to launchd when the parent terminates.
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; sleep 0.5; /usr/bin/open \"\(dstApp)\""
        let relaunch = Process()
        relaunch.launchPath = "/bin/bash"
        relaunch.arguments = ["-c", script]
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

    // MARK: - Version comparison

    static func isNewer(latest: String, current: String) -> Bool {
        let l = parse(latest)
        let c = parse(current)
        for i in 0..<3 where l[i] != c[i] {
            return l[i] > c[i]
        }
        return false
    }

    private static func parse(_ version: String) -> [Int] {
        // Strip any prerelease suffix like "-beta.1"
        let clean = version.split(separator: "-").first.map(String.init) ?? version
        var parts = clean.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        return Array(parts.prefix(3))
    }

    private static func stripV(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    // MARK: - Errors

    enum UpdaterError: LocalizedError {
        case network(String)
        case install(String)

        var errorDescription: String? {
            switch self {
            case .network(let msg): return msg
            case .install(let msg): return msg
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

    init(
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.progressHandler = progress
        self.completionHandler = completion
    }

    private func finishOnce(_ result: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
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
