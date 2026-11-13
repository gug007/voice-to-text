import AppKit
import UniformTypeIdentifiers

/// Choosing an audio or video file to transcribe as a conversation. The
/// Conversations pane's Upload File… and the menu bar's Transcribe File… both
/// open this panel and feed `MeetingController.importMedia`, so the two can't
/// disagree about which files are accepted.
enum MediaFileImport {
    /// What the open panel offers, and what a dropped file is checked against.
    nonisolated static let acceptedContentTypes: [UTType] = [.audiovisualContent, .audio, .movie]

    /// Whether a file can be taken right now: Upload File… is only offered
    /// while the conversation recorder is free.
    static var isAvailable: Bool {
        !MeetingController.shared.isBusy && !AppUpdater.shared.isFinishingInstall
    }

    /// Picks a file and transcribes it. `revealsFailure` is for callers with no
    /// pane on screen: a failed import opens Conversations, where the card explains it.
    static func chooseAndImport(revealsFailure: Bool = false) {
        guard isAvailable else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = acceptedContentTypes
        panel.message = "Choose an audio or video file to transcribe."
        panel.prompt = "Transcribe"
        // From the menu bar the app may have no window and no Dock icon; the
        // panel has to come up in front of whatever the user was using.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            let controller = MeetingController.shared
            await controller.importMedia(url: url)
            if revealsFailure, case .error = controller.state {
                WindowOpener.shared.showMain(section: .meetings)
            }
        }
    }

    /// Pure and nonisolated: called from the nonisolated drop-provider closures.
    nonisolated static func isMediaType(_ identifier: String) -> Bool {
        UTType(identifier).map(isMedia) ?? false
    }

    nonisolated static func isMedia(_ type: UTType) -> Bool {
        acceptedContentTypes.contains { type.conforms(to: $0) }
    }

    /// Whether a URL points at audio or video we can import — the open panel's
    /// accepted content types.
    static func isSupportedMedia(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        return type.map(isMedia) ?? false
    }
}
