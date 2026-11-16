import AppKit
import Foundation
import Observation
import OSLog

/// "Control from iPhone": runs this Mac's embedded Tailscale node while the
/// switch is on and serves the remote API (`RemoteProtocol`) on the tailnet
/// once the node is signed in. Off by default; with it off the node is never
/// created, so the app does no Tailscale networking at all.
@MainActor
@Observable
final class RemoteControlController {
    static let shared = RemoteControlController()

    static let enabledKey = "remote.iphoneEnabled"

    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            apply()
        }
    }

    let tailnet: TailnetController

    /// The device that last reached the API, for the settings status line.
    struct Client: Equatable {
        let name: String
        let at: Date
    }

    private(set) var lastClient: Client?
    /// Why the tailnet listener couldn't open, while it can't.
    private(set) var listenError: String?

    @ObservationIgnored private var server: RemoteHTTPServer?
    /// Set by the Sign In button and cleared once signed in, so a sign-in page
    /// opens in the browser only because the user asked for one, and once.
    @ObservationIgnored private var browserRequested = false
    @ObservationIgnored private var openedLoginURL: URL?
    #if DEBUG
    @ObservationIgnored private var loopbackServer: RemoteHTTPServer?
    #endif

    private init() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: false])
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        tailnet = TailnetController(settings: { RemoteControlController.tailnetSettings() })
        tailnet.onStateChange = { [weak self] state in self?.tailnetChanged(state) }
    }

    /// Call once at launch: brings the node back up if the switch was left on.
    func applyAtLaunch() {
        apply()
        #if DEBUG
        startLoopbackIfRequested()
        if isEnabled, UserDefaults.standard.bool(forKey: "debugRemoteSignIn") { signIn() }
        #endif
    }

    func apply() {
        if isEnabled {
            tailnet.start()
        } else {
            stopListening()
            tailnet.stop()
            browserRequested = false
            lastClient = nil
        }
    }

    func signIn() {
        browserRequested = true
        openedLoginURL = nil
        tailnet.signIn()
    }

    /// Opens the pending sign-in page again (the user closed the tab).
    func openSignInPage() {
        guard case .needsLogin(let url) = tailnet.state else { return }
        openLoginPage(url)
    }

    func cancelSignIn() {
        browserRequested = false
        tailnet.cancelSignIn()
    }

    func signOut() {
        browserRequested = false
        lastClient = nil
        Task { await tailnet.signOut() }
    }

    /// Starts the node again after it failed to start or to sign in.
    func retry() {
        tailnet.stop()
        if isEnabled { tailnet.start() }
    }

    /// Closes the listeners without waiting on the node; for app quit.
    func stopServing() {
        stopListening()
        #if DEBUG
        loopbackServer?.stop()
        loopbackServer = nil
        #endif
    }

    // MARK: - Node and listener

    nonisolated static func tailnetSettings() -> TailnetController.Settings {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceToText", isDirectory: true)
        // The dev build from scripts/dev.sh gets its own node, so running it
        // beside the release build never shares one identity between two
        // processes.
        let folder = Bundle.main.bundleIdentifier == "voice-to-text-ai.VoiceToText" ? "Tailscale" : "Tailscale-dev"
        return TailnetController.Settings(
            hostName: RemoteHostName.mac(computerName: macName),
            directory: support.appendingPathComponent(folder, isDirectory: true)
        )
    }

    nonisolated static var macName: String {
        Host.current().localizedName ?? "Mac"
    }

    private func tailnetChanged(_ state: TailnetState) {
        switch state {
        case .running:
            browserRequested = false
            openedLoginURL = nil
            startListening()
        case .needsLogin(let url):
            stopListening()
            if browserRequested, openedLoginURL != url { openLoginPage(url) }
        case .off, .starting, .signedOut, .connecting, .failed:
            stopListening()
        }
    }

    private func openLoginPage(_ url: URL) {
        openedLoginURL = url
        #if DEBUG
        // Lets a scripted check confirm the page would open without signing
        // anyone in: the URL goes to the log instead of the browser.
        if UserDefaults.standard.bool(forKey: "debugRemoteNoBrowser") {
            AppLog.remote.notice("Tailscale sign-in page (not opened): \(url.absoluteString, privacy: .public)")
            return
        }
        #endif
        NSWorkspace.shared.open(url)
    }

    private func startListening() {
        guard server == nil, let handle = tailnet.handle else { return }
        do {
            let socket = try TailnetListenerSocket(tailscale: handle, port: RemoteProtocol.port)
            let server = makeServer(listener: socket, authorize: TailnetListenerSocket.authorizer(tailscale: handle))
            server.start()
            self.server = server
            listenError = nil
            AppLog.remote.notice("Remote API listening on the tailnet, port \(RemoteProtocol.port, privacy: .public)")
        } catch {
            listenError = error.localizedDescription
            AppLog.remote.error("Remote API couldn't listen: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopListening() {
        server?.stop()
        server = nil
    }

    private func makeServer(
        listener: RemoteListenerSocket,
        authorize: @escaping RemoteHTTPServer.Authorizer
    ) -> RemoteHTTPServer {
        RemoteHTTPServer(
            listener: listener,
            authorize: authorize,
            observe: { event in
                Task { @MainActor in RemoteControlController.shared.record(event) }
            },
            handle: { route, request, _ in
                await RemoteRequestRouter.respond(to: route, request: request)
            }
        )
    }

    private func record(_ event: RemoteHTTPServer.Event) {
        switch event {
        case .served(let peer):
            let name = peer?.machineName ?? "iPhone"
            if lastClient?.name != name || Date().timeIntervalSince(lastClient?.at ?? .distantPast) > 30 {
                lastClient = Client(name: name, at: Date())
            }
        case .denied:
            break
        }
    }

    #if DEBUG
    /// `-debugRemoteLoopback YES`: the same API on 127.0.0.1 over plain TCP
    /// with the owner check bypassed, so the iPhone simulator can drive it
    /// without a Tailscale account. Never compiled into Release.
    private func startLoopbackIfRequested() {
        guard UserDefaults.standard.bool(forKey: "debugRemoteLoopback"), loopbackServer == nil else { return }
        do {
            let socket = try LoopbackListenerSocket(port: RemoteProtocol.port)
            let anyone = TailnetStatus.Node(id: "", hostName: "", dnsName: "", addresses: [], userID: nil, isOnline: true, tags: [])
            let server = makeServer(listener: socket, authorize: { _ in .allow(anyone) })
            server.start()
            loopbackServer = server
            AppLog.remote.notice("Remote API listening on 127.0.0.1:\(RemoteProtocol.port, privacy: .public) (debug loopback)")
        } catch {
            AppLog.remote.error("Debug loopback couldn't listen: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
}

/// Turns a request into a reply from the app's own state. Main actor: it
/// reads `MeetingController` and History, both main-actor objects.
@MainActor
enum RemoteRequestRouter {
    /// How long a stop waits for the recorder to leave `.recording` before
    /// answering with whatever it is now. It answers as soon as the recorder
    /// is transcribing, not when the transcript is done.
    static let commandWait: Duration = .seconds(10)

    static func respond(to route: RemoteRoute, request: RemoteHTTPRequest) async -> RemoteHTTPResponse {
        switch route {
        case .status:
            return .json(status())
        case .startConversation:
            return .json(await startConversation())
        case .stopConversation:
            return .json(await stopConversation())
        case .conversations:
            return .json(RemoteConversationList.make(from: RecordingHistoryStore.shared.entries))
        case .conversation(let id):
            guard let entry = conversation(id) else { return .error(404, "That conversation isn't on this Mac.") }
            return .json(entry)
        case .audio(let id):
            return await audio(id)
        }
    }

    static func status() -> RemoteStatus {
        let controller = MeetingController.shared
        let state: RemoteStatus.State
        var message: String?
        switch controller.state {
        case .idle:
            state = .idle
            message = controller.lastSavedSummary
        case .recording:
            state = .recording
        case .transcribing:
            state = .transcribing
        case .importing:
            state = .importing
        case .error(let text):
            state = .error
            message = text
        }
        return RemoteStatus(
            state: state,
            elapsed: state == .recording ? controller.elapsed : 0,
            message: message,
            mac: macName,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            protocol: RemoteProtocol.version
        )
    }

    private static let macName = RemoteControlController.macName

    /// Starts only from idle (or a dismissed error); anything else answers
    /// with the current status. Never prompts on the Mac: a missing
    /// permission comes back as the error state with its message.
    private static func startConversation() async -> RemoteStatus {
        let controller = MeetingController.shared
        guard controller.hotkeyState == .idle else { return status() }
        AppLog.remote.notice("iPhone asked to start a conversation")
        await controller.start(promptForPermissions: false)
        return status()
    }

    private static func stopConversation() async -> RemoteStatus {
        let controller = MeetingController.shared
        guard controller.state == .recording else { return status() }
        AppLog.remote.notice("iPhone asked to stop the conversation")
        #if DEBUG
        // Lets the scripted end-to-end check record for a few seconds and
        // still leave History untouched.
        if UserDefaults.standard.bool(forKey: "debugRemoteStopCancels") {
            await controller.cancel()
            return status()
        }
        #endif
        Task { await controller.stop() }
        await waitUntil { controller.state != .recording }
        return status()
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: commandWait)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func conversation(_ id: UUID) -> RecordingHistoryEntry? {
        RecordingHistoryStore.shared.entries.first { $0.id == id && $0.source == .meeting }
    }

    private static func audio(_ id: UUID) async -> RemoteHTTPResponse {
        guard let entry = conversation(id) else { return .error(404, "That conversation isn't on this Mac.") }
        let source = RecordingHistoryStore.shared.audioURL(for: entry)
        guard FileManager.default.fileExists(atPath: source.path) else {
            return .error(404, "This conversation's audio is no longer on the Mac.")
        }
        do {
            let copy = try await RemoteAudioCache.shared.m4a(for: id, source: source)
            let size = (try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0 else { return .error(500, "The audio couldn't be prepared.") }
            return RemoteHTTPResponse(status: 200, contentType: "audio/mp4", body: .file(copy, length: Int64(size)))
        } catch {
            AppLog.remote.error("Couldn't prepare a conversation's audio for the iPhone: \(error.localizedDescription, privacy: .public)")
            return .error(500, "The audio couldn't be prepared.")
        }
    }
}
