import Foundation
import Observation
import OSLog
import TailscaleKit
import UIKit

nonisolated struct RemoteMac: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let address: String
    let port: UInt16
    let isOnline: Bool

    init(id: String, name: String, address: String, port: UInt16 = RemoteProtocol.port, isOnline: Bool) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.isOnline = isOnline
    }

    init?(node: TailnetStatus.Node) {
        let dnsName = node.dnsName.hasSuffix(".") ? String(node.dnsName.dropLast()) : node.dnsName
        guard let address = dnsName.lowercased().hasSuffix(".ts.net") ? dnsName : node.preferredAddress else { return nil }
        self.init(id: node.id, name: Self.displayName(node.machineName), address: address, isOnline: node.isOnline)
    }

    private static func displayName(_ machine: String) -> String {
        let prefix = RemoteHostName.macPrefix + "-"
        guard machine.lowercased().hasPrefix(prefix) else { return "Mac" }
        return String(machine.dropFirst(prefix.count))
    }
}

protocol MacTransport {
    func session() async throws -> URLSession
    func baseURL(for mac: RemoteMac) -> URL?
}

struct TailnetTransport: MacTransport {
    let node: TailscaleNode
    let cache: SessionCache

    func session() async throws -> URLSession {
        try await cache.session(for: node) { [node] in
            let (configuration, _) = try await URLSessionConfiguration.tailscaleSession(node)
            configuration.timeoutIntervalForRequest = 15
            configuration.waitsForConnectivity = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: configuration)
        }
    }

    func baseURL(for mac: RemoteMac) -> URL? {
        let host = mac.address.contains(":") ? "[\(mac.address)]" : mac.address
        return URL(string: "http://\(host):\(mac.port)")
    }
}

final class SessionCache {
    private var node: ObjectIdentifier?
    private var cached: URLSession?
    private var pending: Task<URLSession, Error>?

    func session(for node: TailscaleNode, make: @escaping () async throws -> URLSession) async throws -> URLSession {
        let key = ObjectIdentifier(node)
        if self.node == key, let cached { return cached }
        if self.node != key {
            clear()
            self.node = key
        }
        let task = pending ?? Task { try await make() }
        pending = task
        do {
            let session = try await task.value
            if pending == task {
                pending = nil
                if self.node == key { cached = session }
            }
            guard cached === session else {
                session.invalidateAndCancel()
                throw MacRemoteError.notConnected
            }
            return session
        } catch {
            if pending == task { pending = nil }
            throw error
        }
    }

    func clear() {
        pending?.cancel()
        pending = nil
        cached?.invalidateAndCancel()
        cached = nil
        node = nil
    }
}

#if DEBUG
struct LoopbackTransport: MacTransport {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    func session() async throws -> URLSession { Self.session }

    func baseURL(for mac: RemoteMac) -> URL? {
        URL(string: "http://127.0.0.1:\(mac.port)")
    }
}
#endif

enum MacRemoteError: LocalizedError {
    case notConnected
    case refused
    case server(String)
    case badReply

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to a Mac."
        case .refused: return "The Mac didn't accept this iPhone. Sign in to the same Tailscale account on both."
        case .server(let message): return message
        case .badReply: return "The Mac sent a reply this version can't read. Update Voice to Text on both devices."
        }
    }
}

@Observable
final class MacRemote {
    static let shared = MacRemote()

    let tailnet: TailnetController
    let listener = LiveListener()

    private(set) var links: [MacLink] = []

    @ObservationIgnored private let sessions = SessionCache()
    @ObservationIgnored private(set) var isForeground = false

    private static let enabledKey = "remote.tailscaleEnabled"

    private var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    var isLoopback: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "debugRemoteLoopback")
        #else
        false
        #endif
    }

    private init() {
        tailnet = TailnetController(settings: {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return TailnetController.Settings(
                hostName: RemoteHostName.phone(deviceName: UIDevice.current.name),
                directory: base.appendingPathComponent("Tailscale", isDirectory: true)
            )
        })
        listener.onEnd = { [weak self] in self?.listeningEnded() }
        observeMacs()
        reconcile()
    }

    var isSignedIn: Bool { isLoopback || tailnet.state.isRunning }

    private var isSigningIn: Bool {
        switch tailnet.state {
        case .needsLogin, .connecting: return true
        default: return false
        }
    }

    var macs: [RemoteMac] {
        #if DEBUG
        if isLoopback { return Self.loopbackMacs }
        #endif
        guard tailnet.state.isRunning else { return [] }
        return (tailnet.status?.ownMacs ?? []).compactMap(RemoteMac.init(node:))
    }

    #if DEBUG
    private static var loopbackMacs: [RemoteMac] {
        let ports = (UserDefaults.standard.string(forKey: "debugRemoteLoopbackPorts") ?? "")
            .split(separator: ",")
            .compactMap { UInt16($0.trimmingCharacters(in: .whitespaces)) }
        guard !ports.isEmpty else {
            return [RemoteMac(id: "loopback", name: "This Mac", address: "127.0.0.1", isOnline: true)]
        }
        return ports.map {
            RemoteMac(id: "loopback-\($0)", name: "Mac on port \($0)", address: "127.0.0.1", port: $0, isOnline: true)
        }
    }
    #endif

    var homeLinks: [MacLink] {
        guard isSignedIn else { return [] }
        return links.filter { $0.connection == .connected || $0.mac.isOnline }
    }

    var connectedLinks: [MacLink] {
        guard isSignedIn else { return [] }
        return links.filter { $0.connection == .connected }
    }

    func link(id: String) -> MacLink? {
        links.first { $0.id == id }
    }

    func signIn() {
        isEnabled = true
        tailnet.signIn()
    }

    func cancelSignIn() {
        tailnet.cancelSignIn()
    }

    static var liveClientID: String {
        let key = "remote.liveClientID"
        if let id = UserDefaults.standard.string(forKey: key), UUID(uuidString: id) != nil { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    func listenState(for link: MacLink) -> LiveListener.State {
        listener.state(for: link)
    }

    func startListening(_ link: MacLink) {
        listener.start(link)
    }

    func toggleListening(_ link: MacLink) {
        if listener.linkID == link.id, listener.isActive {
            listener.stop()
        } else {
            listener.start(link)
        }
    }

    func stopListening() async {
        await listener.stopAndWait()
    }

    func recordingEnded(on link: MacLink) {
        listener.clear(linkID: link.id)
    }

    func signOut() async {
        listener.stop()
        await tailnet.signOut()
        tailnet.stop()
        isEnabled = false
        sessions.clear()
        links.forEach { $0.stopPolling() }
        links = []
        try? FileManager.default.removeItem(at: Self.audioDirectory)
    }

    func setForeground(_ active: Bool) {
        guard active != isForeground else { return }
        isForeground = active
        if active {
            if isEnabled, !isLoopback { tailnet.start() }
            reconcile()
            links.forEach { $0.startPolling() }
        } else {
            let kept = listener.isActive ? listener.linkID : nil
            links.forEach { if $0.id != kept { $0.stopPolling() } }
            if kept == nil { suspendNetwork() }
        }
    }

    private func listeningEnded() {
        guard !isForeground else { return }
        links.forEach { $0.stopPolling() }
        suspendNetwork()
    }

    private func suspendNetwork() {
        guard !isLoopback, !isSigningIn else { return }
        sessions.clear()
        tailnet.stop()
    }

    static var audioDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacAudio", isDirectory: true)
    }

    func audioURL(_ id: UUID) -> URL {
        Self.audioDirectory.appendingPathComponent("\(id.uuidString).m4a")
    }

    func hasAudio(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: audioURL(id).path)
    }

    func currentTransport() throws -> MacTransport {
        #if DEBUG
        if isLoopback { return LoopbackTransport() }
        #endif
        guard let node = tailnet.node, tailnet.state.isRunning else { throw MacRemoteError.notConnected }
        return TailnetTransport(node: node, cache: sessions)
    }

    private func observeMacs() {
        withObservationTracking {
            _ = macs
            _ = tailnet.status
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reconcile()
                self?.observeMacs()
            }
        }
    }

    private func reconcile() {
        guard isSignedIn, isLoopback || tailnet.status != nil else { return }
        let current = macs
        var byID: [String: RemoteMac] = [:]
        for mac in current where byID[mac.id] == nil { byID[mac.id] = mac }
        var kept: [MacLink] = []
        for link in links {
            if let mac = byID.removeValue(forKey: link.id) {
                link.update(mac)
                kept.append(link)
            } else {
                link.stopPolling()
                listener.clear(linkID: link.id)
            }
        }
        for mac in current {
            guard byID.removeValue(forKey: mac.id) != nil else { continue }
            let link = MacLink(mac: mac, remote: self)
            kept.append(link)
            if isForeground { link.startPolling() }
        }
        if kept.map(ObjectIdentifier.init) != links.map(ObjectIdentifier.init) { links = kept }
    }

    static func complete(_ task: URLSessionDownloadTask, movingTo destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = DownloadCompletion { result in continuation.resume(with: result) }
            delegate.destination = destination
            task.delegate = delegate
            task.resume()
        }
    }

    static func message(for error: Error) -> String {
        if let remote = error as? MacRemoteError { return remote.errorDescription ?? "Something went wrong." }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut: return "The Mac didn't answer in time."
            case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .notConnectedToInternet:
                return "The Mac isn't reachable. Check that it's awake and Voice to Text is running."
            case .cancelled: return "Cancelled."
            default: break
            }
        }
        return error.localizedDescription
    }
}

private nonisolated final class DownloadCompletion: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var destination: URL?
    private let done: @Sendable (Result<Void, Error>) -> Void
    private let lock = NSLock()
    private var finished = false

    init(done: @escaping @Sendable (Result<Void, Error>) -> Void) {
        self.done = done
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destination else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            finish(.failure(status == 404
                ? MacRemoteError.server("This conversation's audio is no longer on the Mac.")
                : MacRemoteError.server("The Mac couldn't send the audio (\(status)).")))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) } else { finish(.success(())) }
    }

    private func finish(_ result: Result<Void, Error>) {
        let first = lock.withLock {
            defer { finished = true }
            return !finished
        }
        if first { done(result) }
    }
}
