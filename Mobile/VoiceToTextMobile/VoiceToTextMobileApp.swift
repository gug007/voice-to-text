import SwiftUI

@main
struct VoiceToTextMobileApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    Transcriber.shared.resumePendingWork()
                    #if DEBUG
                    await DebugLaunch.run()
                    #endif
                }
        }
    }
}

#if DEBUG
enum DebugLaunch {
    static var openFirst: Bool { UserDefaults.standard.bool(forKey: "debugOpenFirst") }
    static var tab: String? { UserDefaults.standard.string(forKey: "debugTab") }

    static func run() async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "debugDownloadModel") {
            Transcriber.shared.prepareModel()
        }
        if let path = defaults.string(forKey: "debugImport") {
            await Importer.shared.importFile(URL(fileURLWithPath: path))
        }
        if let command = defaults.string(forKey: "debugRemote") {
            await runRemote(command)
        }
    }

    static func waitForMac() async -> MacLink? {
        let wanted = UserDefaults.standard.string(forKey: "debugRemoteMac")
        for _ in 0..<100 {
            if let link = target(wanted), link.connection == .connected { return link }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return target(wanted)
    }

    private static func target(_ name: String?) -> MacLink? {
        let links = MacRemote.shared.links
        guard let name else { return links.first }
        return links.first {
            $0.macName.localizedCaseInsensitiveCompare(name) == .orderedSame
                || $0.mac.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private static func runRemote(_ command: String) async {
        guard let link = await waitForMac() else { return }
        switch command {
        case "start":
            await link.startRecording()
        case "stop":
            await link.stopRecording()
        case "cycle":
            await link.startRecording()
            if let seconds = Double(UserDefaults.standard.string(forKey: "debugRemoteHold") ?? "") {
                try? await Task.sleep(for: .seconds(seconds))
            }
            await link.stopRecording()
        default:
            break
        }
    }
}
#endif
