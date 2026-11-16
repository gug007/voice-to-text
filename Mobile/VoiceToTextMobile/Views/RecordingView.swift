import SwiftUI

struct RecordingView: View {
    let onFinish: () -> Void
    let onDiscard: () -> Void

    @State private var confirmDiscard = false

    var body: some View {
        let recorder = Recorder.shared
        VStack(spacing: 0) {
            HStack {
                Button("Discard", role: .destructive) { confirmDiscard = true }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(recorder.phase == .recording ? Palette.live : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(recorder.phase == .interrupted ? "Paused" : "Recording")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(DurationFormat.clock(recorder.elapsed))
                .font(.system(size: 72, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.top, 8)
                .accessibilityLabel("Elapsed time \(DurationFormat.clock(recorder.elapsed))")

            LevelMeter(levels: recorder.levels)
                .frame(height: 72)
                .padding(.horizontal, 36)
                .padding(.top, 28)

            if recorder.phase == .interrupted {
                VStack(spacing: 10) {
                    Text("Another app took the microphone. What was recorded so far is safe.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Resume") { recorder.resumeAfterInterruption() }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 36)
                .padding(.top, 20)
            }

            Spacer()

            Button(action: onFinish) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 4)
                        .frame(width: 92, height: 92)
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Palette.live)
                        .frame(width: 36, height: 36)
                }
            }
            .accessibilityLabel("Stop and transcribe")

            Text("Keeps recording when the screen is locked")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard recording", role: .destructive) {
                recorder.cancel()
                onDiscard()
            }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("The audio recorded so far will be deleted.")
        }
        .interactiveDismissDisabled()
    }
}

struct LevelMeter: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 4) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(Palette.live)
                        .frame(height: max(4, CGFloat(levels[index]) * proxy.size.height))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.linear(duration: 0.08), value: levels)
        }
        .accessibilityHidden(true)
    }
}
