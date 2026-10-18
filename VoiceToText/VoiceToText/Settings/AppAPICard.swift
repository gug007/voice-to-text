import SwiftUI

/// Toggle for the local app API (`ExternalAPIController`): whether other apps
/// on this Mac may record and transcribe through VoiceToText with their own
/// recorder UI.
struct AppAPICard: View {
    @Bindable private var api = ExternalAPIController.shared

    var body: some View {
        Plate {
            SettingsToggleRow(
                title: "Allow other apps to dictate",
                subtitle: "Apps like lpm can record and transcribe with your model, showing their own recorder instead of VoiceToText's. Only apps running as you on this Mac can connect.",
                isOn: $api.isEnabled
            )
        }
    }
}
