import SwiftUI

/// Picker for the "review before paste" setting (`ReviewPolicy`). Until
/// `review.mode` is written the mode follows the old `review.beforePaste` Bool.
struct ReviewBeforePasteCard: View {
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
        Plate {
            SettingHeader(title: "Review before pasting", subtitle: Self.subtitle(for: mode.wrappedValue)) {
                Picker("Review before pasting", selection: mode) {
                    ForEach(ReviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
        }
    }

    static func subtitle(for mode: ReviewMode) -> String {
        switch mode {
        case .always:
            return "Edit, paste, or cancel — nothing types until you confirm."
        case .longTakes:
            return "Takes longer than \(Int(ReviewPolicy.defaultLongTakeSeconds)) seconds open for review. Shorter ones paste straight away."
        case .never:
            return "Text is pasted as soon as it's transcribed."
        }
    }
}
