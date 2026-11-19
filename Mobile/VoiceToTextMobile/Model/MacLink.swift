import Foundation
import Observation
import OSLog

@Observable
final class MacLink: Identifiable {
    enum Connection: Equatable {
        case idle
        case connecting
        case connected
        case unreachable
    }

    let id: String

    private(set) var mac: RemoteMac
    private(set) var connection: Connection = .idle
    private(set) var status: RemoteStatus?
    private(set) var statusReceivedAt = Date()
    private(set) var isSending = false
    private(set) var commandError: String?
    private(set) var lastFailure: String?
    private(set) var conversations: [RemoteConversationRow] = []
    private(set) var conversationsLoaded = false
    private(set) var conversationsError: String?
    private(set) var isLoadingConversations = false
    private(set) var downloadProgress: [UUID: Double] = [:]
    private(set) var downloadErrors: [UUID: String] = [:]

    @ObservationIgnored private var details: [UUID: RecordingHistoryEntry] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private unowned let remote: MacRemote

    init(mac: RemoteMac, remote: MacRemote) {
        id = mac.id
        self.mac = mac
        self.remote = remote
    }

    var macName: String {
        status?.mac ?? mac.name
    }

    var shortName: String {
        MacName.short(macName, among: remote.homeLinks.map(\.macName))
    }

    func elapsed(at date: Date) -> Double {
        guard let status, status.state == .recording else { return 0 }
        return status.elapsed + max(0, date.timeIntervalSince(statusReceivedAt))
    }

    func update(_ mac: RemoteMac) {
        if mac != self.mac { self.mac = mac }
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.remote.isSignedIn {
                    await self.pollOnce()
                } else {
                    self.failures = 0
                    if self.connection != .idle { self.connection = .idle }
                }
                try? await Task.sleep(for: .seconds(self.pollDelay))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        connection = .idle
    }

    func retry() {
        failures = 0
        connection = .connecting
        if pollTask != nil {
            pollTask?.cancel()
            pollTask = nil
            startPolling()
        } else {
            Task { await pollOnce() }
        }
    }

    func startRecording() async {
        await send(RemoteProtocol.Path.startConversation)
    }

    var canStopAndSave: Bool {
        status?.stopAndSave == true
    }

    func stopRecording(transcribe: Bool = true) async {
        await send(transcribe ? RemoteProtocol.Path.stopConversation : RemoteProtocol.Path.saveConversation)
    }

    func refreshConversations() async {
        guard remote.isSignedIn, !isLoadingConversations else { return }
        isLoadingConversations = true
        defer { isLoadingConversations = false }
        do {
            let list: RemoteConversationList = try await request(RemoteProtocol.Path.conversations)
            conversations = list.conversations
            conversationsError = nil
        } catch {
            conversationsError = MacRemote.message(for: error)
        }
        conversationsLoaded = true
    }

    func cachedDetail(_ id: UUID) -> RecordingHistoryEntry? {
        details[id]
    }

    func detail(_ id: UUID) async throws -> RecordingHistoryEntry {
        let entry: RecordingHistoryEntry = try await request(RemoteProtocol.Path.conversation(id))
        details[id] = entry
        return entry
    }

    func downloadAudio(_ id: UUID) async {
        guard downloadProgress[id] == nil, !remote.hasAudio(id) else { return }
        downloadErrors[id] = nil
        downloadProgress[id] = 0
        defer { downloadProgress[id] = nil }
        let destination = remote.audioURL(id)
        do {
            let transport = try remote.currentTransport()
            guard let base = transport.baseURL(for: mac),
                  let url = URL(string: RemoteProtocol.Path.audio(id), relativeTo: base) else { throw MacRemoteError.notConnected }
            var request = URLRequest(url: url)
            request.timeoutInterval = 300
            let session = try await transport.session()
            try FileManager.default.createDirectory(at: MacRemote.audioDirectory, withIntermediateDirectories: true)
            let task = session.downloadTask(with: request)
            let finished = Task { try await MacRemote.complete(task, movingTo: destination) }
            while task.state != .completed, task.state != .canceling {
                downloadProgress[id] = task.progress.fractionCompleted
                try? await Task.sleep(for: .milliseconds(200))
            }
            try await finished.value
        } catch {
            try? FileManager.default.removeItem(at: destination)
            downloadErrors[id] = MacRemote.message(for: error)
        }
    }

    func liveAudioRequest() async throws -> (URLSession, URLRequest) {
        let transport = try remote.currentTransport()
        guard let base = transport.baseURL(for: mac),
              let url = URL(string: "\(RemoteProtocol.Path.liveAudio)?client=\(MacRemote.liveClientID)", relativeTo: base)
        else { throw MacRemoteError.notConnected }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return (try await transport.session(), request)
    }

    private var pollDelay: Double {
        failures < 3 ? 1.0 : min(15.0, pow(2.0, Double(failures - 2)))
    }

    private static func diagnostic(_ error: Error, address: String) -> String {
        if let remote = error as? MacRemoteError { return "\(remote.errorDescription ?? "\(remote)") [\(address)]" }
        let ns = error as NSError
        let under = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { ", \($0.domain) \($0.code)" } ?? ""
        return "\(ns.localizedDescription) (\(ns.domain) \(ns.code)\(under)) [\(address)]"
    }

    private func pollOnce() async {
        guard remote.isSignedIn, !isSending else { return }
        if connection == .idle { connection = .connecting }
        do {
            let latest: RemoteStatus = try await request(RemoteProtocol.Path.status, timeout: connection == .connected ? 5 : 12)
            apply(latest)
            failures = 0
            lastFailure = nil
            if !conversationsLoaded { Task { await refreshConversations() } }
        } catch {
            guard !Task.isCancelled else { return }
            failures += 1
            lastFailure = Self.diagnostic(error, address: mac.address)
            if failures >= 2 {
                connection = .unreachable
            }
            AppLog.remote.debug("Mac \(self.mac.name, privacy: .public) status failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func apply(_ latest: RemoteStatus) {
        let wasTranscribing = status.map { $0.state == .transcribing || $0.state == .importing } ?? false
        let finishedTranscribing = wasTranscribing && latest.state != .transcribing && latest.state != .importing
        let stoppedRecording = status?.state == .recording && latest.state != .recording
        status = latest
        statusReceivedAt = Date()
        connection = .connected
        if stoppedRecording { remote.recordingEnded(on: self) }
        if finishedTranscribing || (stoppedRecording && latest.state == .idle) {
            Task { await refreshConversations() }
        }
    }

    private func send(_ path: String) async {
        guard remote.isSignedIn, !isSending else { return }
        isSending = true
        commandError = nil
        defer { isSending = false }
        do {
            let latest: RemoteStatus = try await request(path, method: "POST", timeout: 20)
            apply(latest)
        } catch {
            commandError = MacRemote.message(for: error)
        }
    }

    private func request<Reply: Decodable>(_ path: String, method: String = "GET", timeout: TimeInterval = 15) async throws -> Reply {
        let transport = try remote.currentTransport()
        guard let base = transport.baseURL(for: mac), let url = URL(string: path, relativeTo: base) else {
            throw MacRemoteError.notConnected
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        let session = try await transport.session()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MacRemoteError.badReply }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 403 { throw MacRemoteError.refused }
            let body = try? RemoteProtocol.makeDecoder().decode(RemoteErrorBody.self, from: data)
            throw MacRemoteError.server(body?.error ?? "The Mac answered with an error (\(http.statusCode)).")
        }
        do {
            return try RemoteProtocol.makeDecoder().decode(Reply.self, from: data)
        } catch {
            throw MacRemoteError.badReply
        }
    }
}

nonisolated enum MacName {
    static func short(_ name: String) -> String {
        var trimmed = name.trimmingCharacters(in: .whitespaces)
        if let suffix = trimmed.range(of: #"\s\(\d+\)$"#, options: .regularExpression) {
            trimmed.removeSubrange(suffix)
        }
        for mark in ["\u{2019}s ", "'s "] {
            guard let possessive = trimmed.range(of: mark) else { continue }
            let rest = trimmed[possessive.upperBound...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty {
                trimmed = rest
                break
            }
        }
        return trimmed.isEmpty ? name : trimmed
    }

    static func short(_ name: String, among names: [String]) -> String {
        let candidate = short(name)
        let clashes = names.contains { $0 != name && short($0) == candidate }
        return clashes ? name : candidate
    }
}
