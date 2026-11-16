import SwiftUI

// MARK: - App status, one line

/// What the app is doing right now and whether dictation can run, as one
/// line: "Ready · GPT Transcribe · OpenAI", "Recording…",
/// "No API key · GPT Transcribe · OpenAI". The sidebar chip, the General
/// Start row and the menu-bar header all read it, so they never disagree.
/// Draw its dot with `StatusDot(status.tone)`.
///
/// Reads only observable state (dictation / conversation controllers, the
/// model registry, the key stores, the credit flag), so a view that calls
/// `AppStatus.current()` in its body re-renders when any of it changes.
///
/// ```swift
/// let status = AppStatus.current()
/// HStack { Circle().fill(status.tone.tint).frame(width: 7, height: 7); Text(status.line) }
/// ```
struct AppStatus: Equatable {
    enum Tone: Equatable {
        /// Dictation can run. Green dot (`Palette.signalReady`, the one
        /// "ready" green).
        case ready
        /// Working (loading, transcribing, pasting). Neutral dot.
        case busy
        /// Recording. Red dot.
        case live
        /// Dictation can't run until the user acts. Orange dot.
        case attention

        var tint: Color {
            switch self {
            case .ready: return Palette.signalReady
            case .busy: return Palette.inkFaint
            case .live: return Palette.signalLive
            case .attention: return Palette.signalWarn
            }
        }
    }

    let tone: Tone
    /// "Ready", "Recording…", "No API key".
    let title: String
    /// The dictation model as "Name · Provider" / "Name · On this Mac",
    /// when it adds something.
    let detail: String?

    /// "Ready · GPT Transcribe".
    var line: String {
        guard let detail else { return title }
        return "\(title) · \(detail)"
    }

    @MainActor
    static func current() -> AppStatus {
        let registry = ModelRegistry.shared
        let model = registry.activeModel
        let name = model?.nameWithSource

        switch DictationController.shared.state {
        case .recording: return AppStatus(tone: .live, title: "Recording…", detail: name)
        case .preparing(let loading): return AppStatus(tone: .busy, title: "Loading…", detail: loading)
        case .transcribing: return AppStatus(tone: .busy, title: "Transcribing…", detail: name)
        case .reviewing: return AppStatus(tone: .busy, title: "Reviewing…", detail: name)
        case .delivering: return AppStatus(tone: .busy, title: "Pasting…", detail: name)
        case .idle, .error: break
        }

        switch MeetingController.shared.state {
        case .recording:
            return AppStatus(tone: .live, title: "Recording conversation…", detail: nil)
        case .transcribing, .importing:
            return AppStatus(tone: .busy, title: "Transcribing…", detail: registry.conversationModel?.nameWithSource)
        case .idle, .error: break
        }

        guard let model, let name else {
            return AppStatus(tone: .attention, title: "No model chosen", detail: nil)
        }
        if let provider = model.backend.cloudProvider {
            if !provider.hasAPIKey {
                return AppStatus(tone: .attention, title: "No API key", detail: name)
            }
            if CloudCreditStatus.shared.isOutOfCredit(provider) {
                return AppStatus(tone: .attention, title: "Out of credit", detail: name)
            }
            return AppStatus(tone: .ready, title: "Ready", detail: name)
        }
        switch registry.readiness(for: model.id) {
        case .installed: return AppStatus(tone: .ready, title: "Ready", detail: name)
        case .preparing:
            let title = ModelSwitchPolicy.isLoading(model, registry: registry) ? "Loading…" : "Downloading…"
            return AppStatus(tone: .busy, title: title, detail: name)
        case .notInstalled: return AppStatus(tone: .attention, title: "Not downloaded", detail: name)
        case .failed: return AppStatus(tone: .attention, title: "Needs attention", detail: name)
        }
    }
}

/// The one status dot: 8pt, coloured by tone (ready green, recording red,
/// attention orange, busy grey). Hidden from VoiceOver — the words carry it.
///
/// ```swift
/// HStack { StatusDot(status.tone); Text(status.line) }
/// StatusDot(.ready, size: 6)
/// ```
struct StatusDot: View {
    let tone: AppStatus.Tone
    var size: CGFloat = 8

    init(_ tone: AppStatus.Tone, size: CGFloat = 8) {
        self.tone = tone
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(tone.tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
