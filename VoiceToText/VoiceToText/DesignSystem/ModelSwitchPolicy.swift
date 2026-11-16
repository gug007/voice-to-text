import Foundation

/// The one rule set for switching models from any surface: the sidebar chip
/// menu, General, the Models pane and the menu bar.
///
/// ```swift
/// Picker(…).disabled(!ModelSwitchPolicy.canChangeDictationModel)
/// let choices = ModelCatalog.all.filter(ModelSwitchPolicy.isUsable)
/// ```
@MainActor
enum ModelSwitchPolicy {
    /// A take reads the dictation model when it stops, so the model holds
    /// still from the moment a take starts until it is delivered. An error is
    /// a resting state, so it allows a change.
    static var canChangeDictationModel: Bool {
        switch DictationController.shared.state {
        case .idle, .error: return true
        case .preparing, .recording, .transcribing, .reviewing, .delivering: return false
        }
    }

    /// Whether `model` can be chosen for a role now. A cloud model needs its
    /// provider's key (out of credit still counts: the balance may have been
    /// topped up). A local model needs its files on disk; one that is only
    /// loading or compiling still counts.
    static func isUsable(_ model: ModelDescriptor) -> Bool {
        isUsable(model, registry: ModelRegistry.shared)
    }

    static func isUsable(_ model: ModelDescriptor, registry: ModelRegistry) -> Bool {
        if let provider = model.backend.cloudProvider {
            return provider.hasAPIKey
        }
        return registry.downloadedLocalModelIDs.contains(model.id)
            || registry.readiness(for: model.id).isInstalled
    }

    /// True while a model that was already installed is being loaded into
    /// memory: "Loading…", not "Downloading…". A fresh download's first
    /// CoreML compile is still part of preparing it (progress and Cancel
    /// stay), because the model only joins `downloadedLocalModelIDs` once
    /// that preparation ends.
    static func isLoading(_ model: ModelDescriptor, registry: ModelRegistry) -> Bool {
        guard !model.isCloud, case .preparing = registry.readiness(for: model.id) else { return false }
        return registry.downloadedLocalModelIDs.contains(model.id)
    }
}
