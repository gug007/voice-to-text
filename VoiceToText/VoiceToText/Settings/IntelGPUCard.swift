#if arch(x86_64)
import SwiftUI

/// Intel Macs only: whether the local models may run on the graphics card
/// (`TranscribeGPUPreference`). On by default. When the GPU has failed on this
/// Mac — a crash or hang the transcription worker survived on the CPU — the
/// switch stays where the user put it, and a line says the CPU is in use
/// until the switch is turned again.
struct IntelGPUCard: View {
    @AppStorage(TranscribeGPUPreference.Keys.useGPU) private var useGPU = true
    @AppStorage(TranscribeGPUPreference.Keys.gpuFailure) private var gpuFailure: String?

    var body: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s4) {
                SettingsToggleRow(
                    title: "Use graphics card (GPU)",
                    subtitle: "Local models transcribe faster on the graphics card. If it fails, VoiceToText switches to the processor on its own.",
                    isOn: Binding(
                        get: { useGPU },
                        set: { TranscribeGPUPreference.setUseGPU($0) }
                    )
                )

                if useGPU, gpuFailure != nil {
                    Text("The graphics card failed on this Mac, so local models run on the processor. Turn this off and on to try it again.")
                        .typo(.caption)
                        .foregroundStyle(Palette.signalWarn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
#endif
