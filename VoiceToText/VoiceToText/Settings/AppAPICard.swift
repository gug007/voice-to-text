import SwiftUI

/// Switch for the local app API (`ExternalAPIController`): whether other apps
/// on this Mac may record and transcribe through VoiceToText with their own
/// recorder UI. Its group footer says who can connect.
struct AppAPIRow: View {
    @Bindable private var api = ExternalAPIController.shared

    var body: some View {
        SettingsRow(
            "Allow other apps to dictate",
            caption: "Other apps on this Mac can record and transcribe with your model.",
            isOn: $api.isEnabled
        )
        .help("Apps such as lpm show their own recorder instead of VoiceToText's.")
    }

    /// The App group's footer: it explains the group's last row.
    static let footer = "Other apps show their own recorder, and only ones running as you on this Mac can connect."
}
