import Foundation
import Observation
import OSLog

/// Owns the local app API: serves it while "Allow other apps" is on, and
/// routes each request to `ExternalDictationSession`. See INTEGRATION.md.
@Observable
final class ExternalAPIController {
    static let shared = ExternalAPIController()

    static let enabledKey = "api.enabled"

    /// Whether other apps may record through VoiceToText. On by default — the
    /// socket only accepts processes running as this user.
    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            apply()
        }
    }

    private(set) var isServing = false
    @ObservationIgnored private var server: ExternalAPIServer?

    private init() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var socketPath: String {
        ExternalAPIServer.defaultPath(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    func apply() {
        isEnabled ? serve() : stopServing()
    }

    func stopServing() {
        guard let server else { return }
        self.server = nil
        isServing = false
        // Closing the connections cancels their session (`connectionClosed`).
        server.stop()
    }

    private func serve() {
        guard server == nil else { return }
        let server = ExternalAPIServer(path: socketPath)
        do {
            try server.start(
                onRequest: { request, connection in
                    Task { @MainActor in
                        await ExternalAPIController.shared.handle(request, from: connection)
                    }
                },
                onDisconnect: { connection in
                    Task { @MainActor in
                        await ExternalDictationSession.shared.connectionClosed(connection)
                    }
                }
            )
            self.server = server
            isServing = true
        } catch {
            AppLog.app.error("App API could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ request: ExternalAPI.Request, from connection: ExternalAPIConnection) async {
        let session = ExternalDictationSession.shared
        switch request.method {
        case .status:
            var result = session.statusJSON()
            result["api"] = ExternalAPI.version
            result["app"] = "VoiceToText"
            result["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            result["owner"] = session.owns(connection)
            connection.send(ExternalAPI.response(id: request.id, result: result))
        case .start:
            await session.start(id: request.id, from: connection, client: request.client)
        case .stop:
            await session.stop(id: request.id, from: connection)
        case .cancel:
            await session.cancel(id: request.id, from: connection)
        }
    }
}
