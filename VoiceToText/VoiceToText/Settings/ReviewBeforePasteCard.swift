import SwiftUI

/// Picker for the "review before paste" setting (`ReviewPolicy`). Until
/// `review.mode` is written the mode follows the old `review.beforePaste` Bool.
struct ReviewBeforePasteRow: View {
    @AppStorage(ReviewPolicy.modeKey) private var storedMode: String?
    @AppStorage(ReviewPolicy.legacyKey) private var legacyBeforePaste: Bool = true

    private var mode: Binding<ReviewMode> {
        Binding(
            get: { ReviewPolicy.mode(storedMode: storedMode, legacyBeforePaste: legacyBeforePaste) },
            set: { newValue in
                let values = ReviewPolicy.values(for: newValue)
                storedMode = values.mode
                legacyBeforePaste = values.legacyBeforePaste
            }
        )
    }

    var body: some View {
        SettingsRow("Review before pasting", caption: Self.caption) {
            Picker("Review before pasting", selection: mode) {
                ForEach(ReviewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .help("Long takes: over \(Self.longTakeSeconds) seconds.")
        }
    }

    private static var longTakeSeconds: Int { Int(ReviewPolicy.longTakeSeconds(in: .standard).rounded()) }

    /// The one fact the segment labels don't carry: what counts as long.
    private static var caption: String {
        "Long takes are those over \(longTakeSeconds) seconds."
    }
}
