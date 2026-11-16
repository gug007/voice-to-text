import Darwin
import Foundation
import OSLog
import libtailscale

/// Where the remote server's connections come from: a file descriptor that
/// turns readable when a connection is waiting, and an accept that returns
/// the connection's descriptor with the caller's address.
nonisolated protocol RemoteListenerSocket: AnyObject, Sendable {
    var descriptor: Int32 { get }
    /// Nil when nothing was waiting after all, or the listener is closed.
    func accept() -> (descriptor: Int32, remoteAddress: String)?
    func close()
}

/// A TCP port on the tailnet, through libtailscale's C API. TailscaleKit's
/// own `Listener` can't serve: its connections only read, and its accept
/// blocks a Swift concurrency thread in poll(2) and closes the listener when
/// that times out. The descriptor libtailscale hands back is one end of a
/// socketpair; each connection arrives on it as its own descriptor with the
/// caller's tailnet address attached.
nonisolated final class TailnetListenerSocket: RemoteListenerSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var listener: Int32

    init(tailscale handle: Int32, port: UInt16) throws {
        var listener: Int32 = 0
        let result = tailscale_listen(handle, "tcp", ":\(port)", &listener)
        guard result == 0 else {
            throw RemoteServerError.listen(Self.errorMessage(handle))
        }
        self.listener = listener
    }

    var descriptor: Int32 {
        lock.withLock { listener }
    }

    func accept() -> (descriptor: Int32, remoteAddress: String)? {
        let listener = descriptor
        guard listener > 0 else { return nil }
        var connection: Int32 = 0
        let accepted = tailscale_accept(listener, &connection)
        guard accepted == 0 else {
            AppLog.remote.error("Tailnet accept failed: \(accepted, privacy: .public), errno \(errno, privacy: .public)")
            return nil
        }
        var buffer = [CChar](repeating: 0, count: 64)
        let found = tailscale_getremoteaddr(listener, connection, &buffer, buffer.count) == 0
        let address = found ? String(cString: buffer) : ""
        AppLog.remote.notice("Tailnet connection from \(address.isEmpty ? "an unknown address" : address, privacy: .public)")
        return (connection, address)
    }

    /// Closing our end tells libtailscale to close the tailnet listener.
    func close() {
        lock.withLock {
            if listener > 0 { Darwin.close(listener) }
            listener = 0
        }
    }

    /// Checks each caller against the node's status read at that moment, so a
    /// device removed from the account or signed in to another one is refused
    /// on its very next request. The read is in memory (no network), and any
    /// failure to read it refuses the caller.
    static func authorizer(tailscale handle: Int32) -> RemoteHTTPServer.Authorizer {
        { address in
            var json: UnsafeMutablePointer<CChar>?
            guard tailscale_status_json(handle, &json) == 0, let json else {
                return .deny("this Mac's Tailscale status is unavailable")
            }
            defer { free(json) }
            guard let status = try? TailnetStatus.decode(Data(bytes: json, count: strlen(json))) else {
                return .deny("this Mac's Tailscale status is unreadable")
            }
            return RemoteAccessPolicy.decide(remoteAddress: address, status: status)
        }
    }

    private static func errorMessage(_ handle: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        tailscale_errmsg(handle, &buffer, buffer.count)
        return String(cString: buffer)
    }
}

#if DEBUG
/// The same server on 127.0.0.1 over plain TCP, for driving the iPhone app
/// from the simulator without a Tailscale account. Debug builds only, and
/// only with `-debugRemoteLoopback YES`.
nonisolated final class LoopbackListenerSocket: RemoteListenerSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var listener: Int32

    init(port: UInt16) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw RemoteServerError.listen(String(cString: strerror(errno))) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fd)
            throw RemoteServerError.listen(message)
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listener = fd
    }

    var descriptor: Int32 {
        lock.withLock { listener }
    }

    func accept() -> (descriptor: Int32, remoteAddress: String)? {
        let listener = descriptor
        guard listener > 0 else { return nil }
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { return nil }
        return (fd, "127.0.0.1")
    }

    func close() {
        lock.withLock {
            if listener > 0 { Darwin.close(listener) }
            listener = 0
        }
    }
}
#endif

nonisolated enum RemoteServerError: LocalizedError {
    case listen(String)

    var errorDescription: String? {
        switch self {
        case .listen(let message): return "Couldn't listen for the iPhone: \(message)"
        }
    }
}

/// Serves HTTP on one listener. Accepts on a serial queue; each connection is
/// read, answered and closed on its own work item, with blocking IO bounded
/// by timeouts, so a slow phone downloading audio holds up nobody else.
///
/// Every connection is checked by `authorize` before anything is parsed into
/// an action; a denied caller gets a 403 and never reaches `handle`.
nonisolated final class RemoteHTTPServer: @unchecked Sendable {
    typealias Authorizer = @Sendable (String) -> RemoteAccessPolicy.Decision
    typealias Handler = @Sendable (RemoteRoute, RemoteHTTPRequest, TailnetStatus.Node?) async -> RemoteHTTPResponse
    typealias Observer = @Sendable (Event) -> Void

    enum Event: Sendable {
        case served(peer: TailnetStatus.Node?)
        case denied(address: String, reason: String)
    }

    /// Beyond this many connections at once the next one gets a 503: the
    /// phone polls one at a time and downloads one file at a time.
    static let maxConnections = 8
    /// How long a caller may take to send its request.
    static let requestTimeout: TimeInterval = 10
    /// A write that makes no progress for this long ends the connection.
    static let writeStallSeconds = 30

    private let listener: RemoteListenerSocket
    private let authorize: Authorizer
    private let handle: Handler
    private let observe: Observer
    private let acceptQueue = DispatchQueue(label: "voice-to-text-ai.VoiceToText.remote.accept")
    private let connectionQueue = DispatchQueue(
        label: "voice-to-text-ai.VoiceToText.remote.connection",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var source: DispatchSourceRead?
    private let lock = NSLock()
    private var active = 0

    init(listener: RemoteListenerSocket, authorize: @escaping Authorizer, observe: @escaping Observer, handle: @escaping Handler) {
        self.listener = listener
        self.authorize = authorize
        self.observe = observe
        self.handle = handle
    }

    func start() {
        acceptQueue.sync {
            guard source == nil else { return }
            let source = DispatchSource.makeReadSource(fileDescriptor: listener.descriptor, queue: acceptQueue)
            source.setEventHandler { [weak self] in self?.acceptOne() }
            source.resume()
            self.source = source
        }
    }

    func stop() {
        acceptQueue.sync {
            source?.cancel()
            source = nil
        }
        listener.close()
    }

    private func acceptOne() {
        guard let (fd, address) = listener.accept() else { return }
        Self.prepare(fd)
        let admitted: Bool = lock.withLock {
            guard active < Self.maxConnections else { return false }
            active += 1
            return true
        }
        guard admitted else {
            connectionQueue.async {
                Self.write(RemoteHTTPResponse.error(503, "Too many connections.").head(), to: fd)
                Self.finish(fd)
            }
            return
        }
        connectionQueue.async { [self] in
            serve(fd, from: address)
            lock.withLock { active -= 1 }
        }
    }

    private func serve(_ fd: Int32, from address: String) {
        defer { Self.finish(fd) }
        let peer: TailnetStatus.Node?
        switch authorize(address) {
        case .allow(let node):
            peer = node.id.isEmpty ? nil : node
        case .deny(let reason):
            AppLog.remote.warning("Remote API refused \(address, privacy: .public): \(reason, privacy: .public)")
            observe(.denied(address: address, reason: reason))
            Self.send(.error(403, "This device isn't allowed to control this Mac."), to: fd)
            return
        }

        let request: RemoteHTTPRequest
        switch Self.readRequest(from: fd) {
        case .complete(let parsed):
            request = parsed
        case .invalid(let status, let reason):
            Self.send(.error(status, reason), to: fd)
            return
        case .incomplete:
            Self.send(.error(408, "The request didn't arrive in time."), to: fd)
            return
        }

        let response: RemoteHTTPResponse
        switch RemoteRoute.match(method: request.method, path: request.path) {
        case .success(let route):
            let handle = self.handle
            response = Self.waitFor { await handle(route, request, peer) }
        case .failure(.notFound):
            response = .error(404, "No such endpoint.")
        case .failure(.methodNotAllowed):
            response = .error(405, "Method not allowed.")
        }
        Self.send(response, to: fd)
        observe(.served(peer: peer))
    }

    // MARK: - Blocking IO

    private static func prepare(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: writeStallSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func readRequest(from fd: Int32) -> RemoteHTTPParser.Outcome {
        let deadline = Date().addingTimeInterval(requestTimeout)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return .incomplete }
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, Int32(remaining * 1000))
            if ready < 0, errno == EINTR { continue }
            guard ready > 0 else { return .incomplete }
            let count = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return .invalid(status: 400, reason: "The connection closed mid-request.") }
            buffer.append(contentsOf: chunk[0..<count])
            let outcome = RemoteHTTPParser.parse(buffer)
            if outcome != .incomplete { return outcome }
        }
    }

    private static func send(_ response: RemoteHTTPResponse, to fd: Int32) {
        guard write(response.head(), to: fd) else { return }
        switch response.body {
        case .data(let data):
            _ = write(data, to: fd)
        case .file(let url, let length):
            guard let file = FileHandle(forReadingAtPath: url.path) else { return }
            defer { try? file.close() }
            var sent: Int64 = 0
            while sent < length {
                let want = Int(min(Int64(256 * 1024), length - sent))
                guard let data = try? file.read(upToCount: want), !data.isEmpty else { return }
                guard write(data, to: fd) else { return }
                sent += Int64(data.count)
            }
        }
    }

    @discardableResult
    private static func write(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return true }
            var left = raw.count
            while left > 0 {
                let written = Darwin.write(fd, pointer, left)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { return false }
                pointer += written
                left -= written
            }
            return true
        }
    }

    /// Half-closes so the reply is delivered in full, gives the caller a
    /// moment to close its side, then closes.
    private static func finish(_ fd: Int32) {
        shutdown(fd, SHUT_WR)
        var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        var scratch = [UInt8](repeating: 0, count: 1024)
        let deadline = Date().addingTimeInterval(1)
        while deadline.timeIntervalSinceNow > 0,
              poll(&poller, 1, Int32(max(1, deadline.timeIntervalSinceNow * 1000))) > 0 {
            let count = scratch.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count <= 0 { break }
        }
        Darwin.close(fd)
    }

    /// Runs `operation` (which hops to the main actor for app state) and
    /// blocks this connection's work item until it returns. Fine here: the
    /// item is a dispatch thread, not one of Swift concurrency's.
    private static func waitFor<T: Sendable>(_ operation: @escaping @Sendable () async -> T) -> T {
        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await operation()
            done.signal()
        }
        done.wait()
        return box.value!
    }
}

private nonisolated final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}
