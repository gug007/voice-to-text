import SwiftUI

/// Toggle for the "review before paste" setting. Backed by the
/// `review.beforePaste` UserDefault, which DictationController reads at the end
/// of each transcription to decide whether to paste directly or show the HUD.
struct ReviewBeforePasteCard: View {
    @AppStorage("review.beforePaste") private var reviewBeforePaste: Bool = true

    var body: some View {
        Plate {
            SettingsToggleRow(
                title: "Review before pasting",
                subtitle: "Edit, paste, or cancel — nothing types until you confirm.",
                isOn: $reviewBeforePaste
            )
        }
    }
}
