import Foundation
import Observation
import OSLog
import TailscaleKit

/// One embedded Tailscale node for this app, compiled into both the Mac app
/// and the iPhone app (Mobile/project.yml lists it). The node lives inside
/// the process: no Tailscale app, no VPN profile, no system extension. Each
/// app owns one instance and decides when it runs; this class only drives
/// the node and reports `state`.
///
/// Nothing here starts the node by itself: `TailscaleNode` isn't created, and
/// no network traffic happens, until the app calls `start()` or `signIn()`.
/// The node keeps its keys in `Settings.directory`, so after one sign-in it
/// comes back signed in on every later start.
///
/// State comes from polling the node's status in memory
/// (`TailscaleNode.statusJSON()`), with the IPN bus watched for the sign-in
/// URL (`BrowseToURL`) and as a nudge to poll sooner. The poll is the source
/// of truth because the bus rides the node's loopback HTTP listener, which
/// the OS can take away from a suspended iOS process.
@MainActor
@Observable
final class TailnetController {
    struct Settings: Sendable {
        let hostName: String
        let directory: URL
    }

    private(set) var state: TailnetState = .off
    private(set) var status: TailnetStatus?

    /// The running node, for the Mac's listener and the phone's URLSession.
    /// Nil whenever `state` is `.off`.
    @ObservationIgnored private(set) var node: TailscaleNode?
    /// libtailscale's handle for the C calls TailscaleKit doesn't wrap (the
    /// Mac's listener). Valid while `node` is set.
    @ObservationIgnored private(set) var handle: Int32?

    /// Called on every change of `state`, after it changes.
    @ObservationIgnored var onStateChange: ((TailnetState) -> Void)?

    @ObservationIgnored private let makeSettings: () -> Settings
    @ObservationIgnored private var localAPI: LocalAPIClient?
    @ObservationIgnored private var bus: MessageProcessor?
    @ObservationIgnored private var busConsumer: TailnetBusConsumer?
    @ObservationIgnored private var lifecycle: Task<Void, Never>?
    /// A node still shutting down. A new one waits for it: two nodes on the
    /// same state directory would fight over its files.
    @ObservationIgnored private var closing: Task<Void, Never>?
    /// Bumped on every start and stop, so a late callback from a node that has
    /// since been stopped is dropped.
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var loginRequested = false
    @ObservationIgnored private var loginStarted = false
    @ObservationIgnored private var browseURL: URL?

    init(settings: @escaping () -> Settings) {
        makeSettings = settings
    }

    var isStarted: Bool { lifecycle != nil }

    // MARK: - Lifecycle

    func start() {
        guard lifecycle == nil else { return }
        session += 1
        let current = session
        setState(loginRequested ? .connecting : .starting)
        let settings = makeSettings()
        lifecycle = Task { [weak self] in
            await self?.run(settings: settings, session: current)
        }
    }

    /// Shuts the node down. The account stays signed in on disk; the next
    /// `start()` reconnects with it.
    func stop() {
        guard lifecycle != nil || node != nil else { return }
        session += 1
        lifecycle?.cancel()
        lifecycle = nil
        bus?.cancel()
        bus = nil
        busConsumer = nil
        localAPI = nil
        status = nil
        handle = nil
        let node = self.node
        self.node = nil
        loginStarted = false
        setState(.off)
        guard let node else { return }
        let previous = closing
        closing = Task {
            await previous?.value
            try? await node.close()
        }
    }

    // MARK: - Account

    /// Starts the interactive sign-in; `state` turns `.needsLogin(url)` once
    /// Tailscale has a page for it. Starts the node first if it isn't running.
    func signIn() {
        loginRequested = true
        browseURL = nil
        guard node != nil else {
            if lifecycle == nil { start() } else { setState(.connecting) }
            return
        }
        setState(.connecting)
        Task { await beginLogin() }
    }

    /// The user closed the sign-in page without finishing.
    func cancelSignIn() {
        loginRequested = false
        loginStarted = false
        browseURL = nil
        if let status { apply(status) }
    }

    /// Logs this node out of its account. The node keeps running, signed out.
    func signOut() async {
        loginRequested = false
        loginStarted = false
        browseURL = nil
        if let localAPI {
            do {
                try await localAPI.logout()
            } catch {
                AppLog.remote.error("Tailscale sign-out failed: \(String(describing: error), privacy: .public)")
            }
        }
        await refresh()
    }

    /// Re-reads the node's status now instead of at the next poll.
    func refresh() async {
        guard let node else { return }
        let current = session
        do {
            let data = try await node.statusJSON()
            let decoded = try TailnetStatus.decode(data)
            guard current == session else { return }
            apply(decoded)
        } catch {
            AppLog.remote.error("Tailscale status unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Internals

    private func run(settings: Settings, session current: Int) async {
        await closing?.value
        let node: TailscaleNode
        do {
            node = try await Self.makeNode(settings)
        } catch {
            guard current == session else { return }
            AppLog.remote.error("Tailscale couldn't start: \(String(describing: error), privacy: .public)")
            lifecycle = nil
            setState(.failed("Tailscale couldn't start. Try again, or restart the app."))
            return
        }
        guard current == session, !Task.isCancelled else {
            try? await node.close()
            return
        }
        self.node = node
        handle = await node.tailscale
        AppLog.remote.notice("Tailscale node started as \(settings.hostName, privacy: .public)")

        let api = LocalAPIClient(localNode: node, logger: TailnetLogSink())
        localAPI = api
        // A strong capture: the controller lives as long as the app, and the
        // consumer goes with the bus when the node stops.
        let consumer = TailnetBusConsumer { notify in
            Task { @MainActor in self.receive(notify, session: current) }
        }
        busConsumer = consumer
        do {
            bus = try await api.watchIPNBus(mask: [.initialState, .noPrivateKeys], consumer: consumer)
        } catch {
            AppLog.remote.error("Tailscale IPN bus unavailable: \(String(describing: error), privacy: .public)")
        }
        if loginRequested { await beginLogin() }

        while !Task.isCancelled, current == session {
            await refresh()
            let pause: Duration = state.isRunning ? .seconds(10) : .milliseconds(1500)
            try? await Task.sleep(for: pause)
        }
    }

    /// `TailscaleNode.init` runs `tailscale_start`, which reads the state
    /// directory and brings up the Go backend: off the main actor.
    private nonisolated static func makeNode(_ settings: Settings) async throws -> TailscaleNode {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: settings.directory, withIntermediateDirectories: true)
            let config = TailscaleKit.Configuration(
                hostName: settings.hostName,
                path: settings.directory.path,
                authKey: nil,
                controlURL: kDefaultControlURL,
                ephemeral: false
            )
            return try TailscaleNode(config: config, logger: TailnetLogSink(directory: settings.directory))
        }.value
    }

    private func beginLogin() async {
        guard let localAPI, !loginStarted else { return }
        loginStarted = true
        do {
            try await localAPI.startLoginInteractive()
        } catch {
            AppLog.remote.error("Tailscale sign-in couldn't start: \(String(describing: error), privacy: .public)")
            loginStarted = false
            loginRequested = false
            setState(.failed("Tailscale sign-in couldn't start. Check the internet connection and try again."))
            return
        }
        await refresh()
    }

    private func receive(_ notify: Ipn.Notify, session current: Int) {
        guard current == session else { return }
        if let raw = notify.BrowseToURL, let url = URL(string: raw), loginRequested {
            browseURL = url
        }
        if let message = notify.ErrMessage, !message.isEmpty {
            AppLog.remote.error("Tailscale: \(message, privacy: .public)")
        }
        Task { await refresh() }
    }

    private func apply(_ status: TailnetStatus) {
        self.status = status
        let derived = TailnetState.derive(
            backendState: status.backendState,
            authURL: status.authURL,
            browseURL: browseURL,
            loginRequested: loginRequested,
            accountName: status.accountName
        )
        if derived.isRunning {
            loginRequested = false
            loginStarted = false
            browseURL = nil
        }
        setState(derived)
    }

    private func setState(_ new: TailnetState) {
        guard new != state else { return }
        state = new
        onStateChange?(new)
    }
}

/// Feeds IPN bus notifications back to the controller.
actor TailnetBusConsumer: MessageConsumer {
    private let onNotify: @Sendable (Ipn.Notify) -> Void

    init(onNotify: @escaping @Sendable (Ipn.Notify) -> Void) {
        self.onNotify = onNotify
    }

    func notify(_ notify: Ipn.Notify) {
        onNotify(notify)
    }

    func error(_ error: any Error) {
        AppLog.remote.error("Tailscale IPN bus: \(String(describing: error), privacy: .public)")
    }
}

/// TailscaleKit's own messages go to the unified log at debug level. The Go
/// backend's verbose log is discarded in Release; a Debug build writes it to
/// `tailscale-debug.log` in the state directory, replaced on every start.
nonisolated struct TailnetLogSink: LogSink {
    let logFileHandle: Int32?

    init(directory: URL? = nil) {
        #if DEBUG
        if let directory {
            let path = directory.appendingPathComponent("tailscale-debug.log").path
            let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
            logFileHandle = fd >= 0 ? fd : -1
            return
        }
        #endif
        logFileHandle = -1
    }

    func log(_ message: String) {
        AppLog.remote.debug("\(message, privacy: .public)")
    }
}
