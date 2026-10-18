import Darwin
import Foundation
import OSLog

/// Serves the local app API on a Unix socket in Application Support. Only
/// processes running as this user can connect: the socket is 0600 and every
/// peer's uid is checked on accept. All socket work runs on one serial queue;
/// requests are handed to `onRequest` from there.
nonisolated final class ExternalAPIServer: @unchecked Sendable {
    enum ServerError: LocalizedError {
        case pathTooLong
        case alreadyServing
        case system(String, Int32)

        var errorDescription: String? {
            switch self {
            case .pathTooLong: return "The API socket path is too long."
            case .alreadyServing: return "Another copy of VoiceToText is already serving the API."
            case .system(let call, let code): return "\(call) failed: \(String(cString: strerror(code)))"
            }
        }
    }

    typealias RequestHandler = @Sendable (ExternalAPI.Request, ExternalAPIConnection) -> Void
    typealias DisconnectHandler = @Sendable (ExternalAPIConnection) -> Void

    let path: String
    private let queue = DispatchQueue(label: "voice-to-text-ai.VoiceToText.api")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [UInt64: ExternalAPIConnection] = [:]
    private var nextConnectionID: UInt64 = 0

    init(path: String) {
        self.path = path
    }

    /// The release build and every other build (the `.dev` one from
    /// scripts/dev.sh) each get their own socket, so both can run side by side.
    static func defaultPath(bundleIdentifier: String?) -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceToText", isDirectory: true)
        let name = bundleIdentifier == "voice-to-text-ai.VoiceToText" ? "api.sock" : "api-dev.sock"
        return support.appendingPathComponent(name).path
    }

    func start(onRequest: @escaping RequestHandler, onDisconnect: @escaping DisconnectHandler) throws {
        try queue.sync {
            guard listenFD < 0 else { return }
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            let fd = try bindListener()
            listenFD = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptPending(onRequest: onRequest, onDisconnect: onDisconnect)
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            acceptSource = source
        }
        AppLog.app.notice("App API listening at \(self.path, privacy: .public)")
    }

    func stop() {
        queue.sync {
            guard listenFD >= 0 else { return }
            acceptSource?.cancel()
            acceptSource = nil
            listenFD = -1
            unlink(path)
            for connection in connections.values { connection.closeOnQueue() }
            connections.removeAll()
        }
    }

    private func bindListener() throws -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw ServerError.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        // A socket file left by a crash is unlinked; one that still answers
        // belongs to a running copy, which keeps it.
        if FileManager.default.fileExists(atPath: path) {
            if Self.answers(&address) { throw ServerError.alreadyServing }
            unlink(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.system("socket", errno) }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw ServerError.system("bind", code)
        }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw ServerError.system("listen", code)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }

    private static func answers(_ address: inout sockaddr_un) -> Bool {
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    private func acceptPending(onRequest: @escaping RequestHandler, onDisconnect: @escaping DisconnectHandler) {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                AppLog.app.warning("App API refused a connection from another user")
                close(fd)
                continue
            }
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            var noSigPipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            nextConnectionID &+= 1
            let id = nextConnectionID
            let connection = ExternalAPIConnection(
                id: id,
                fd: fd,
                queue: queue,
                onLine: { connection, line in
                    switch ExternalAPI.parseRequest(line) {
                    case .success(let request):
                        onRequest(request, connection)
                    case .failure(let failure):
                        connection.send(ExternalAPI.failure(id: failure.id, code: failure.code, message: failure.message))
                    }
                },
                onClose: { [weak self] connection in
                    self?.connections[connection.id] = nil
                    onDisconnect(connection)
                }
            )
            connections[id] = connection
            connection.open()
        }
    }
}

/// One client of the API. Lines in, lines out; closes itself on EOF, on a
/// line too long to be a request, and on a client that stops reading.
nonisolated final class ExternalAPIConnection: @unchecked Sendable {
    let id: UInt64
    private let queue: DispatchQueue
    private let channel: DispatchIO
    private let onLine: (ExternalAPIConnection, Data) -> Void
    private let onClose: (ExternalAPIConnection) -> Void
    private var splitter = ExternalAPI.LineSplitter()
    private var pendingWrites = 0
    private var isClosed = false

    /// A client this far behind isn't reading: level events alone come at
    /// ~15 a second, and buffering them for it forever would grow without
    /// bound.
    private static let maxPendingWrites = 512

    init(
        id: UInt64,
        fd: Int32,
        queue: DispatchQueue,
        onLine: @escaping (ExternalAPIConnection, Data) -> Void,
        onClose: @escaping (ExternalAPIConnection) -> Void
    ) {
        self.id = id
        self.queue = queue
        self.onLine = onLine
        self.onClose = onClose
        channel = DispatchIO(type: .stream, fileDescriptor: fd, queue: queue) { _ in close(fd) }
        channel.setLimit(lowWater: 1)
    }

    /// Must run on the server queue.
    func open() {
        channel.read(offset: 0, length: Int.max, queue: queue) { [weak self] done, data, error in
            guard let self, !self.isClosed else { return }
            if let data, !data.isEmpty {
                for line in self.splitter.append(Data(data)) {
                    self.onLine(self, line)
                }
                if self.splitter.overflowed {
                    AppLog.app.warning("App API client sent an over-long line; closing it")
                    self.closeOnQueue()
                    return
                }
            }
            if done || error != 0 { self.closeOnQueue() }
        }
    }

    func send(_ data: Data) {
        queue.async { [self] in
            guard !isClosed else { return }
            guard pendingWrites < Self.maxPendingWrites else {
                AppLog.app.warning("App API client stopped reading; closing it")
                closeOnQueue()
                return
            }
            pendingWrites += 1
            let payload = data.withUnsafeBytes { DispatchData(bytes: $0) }
            channel.write(offset: 0, data: payload, queue: queue) { [weak self] done, _, error in
                guard let self, done else { return }
                self.pendingWrites -= 1
                if error != 0 { self.closeOnQueue() }
            }
        }
    }

    func closeOnQueue() {
        guard !isClosed else { return }
        isClosed = true
        channel.close(flags: .stop)
        onClose(self)
    }
}
