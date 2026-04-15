import SwiftUI

struct TranscriptionPane: View {
    // Language: empty string = auto-detect (nil to decoder)
    @AppStorage("decoder.language") private var language: String = ""
    @AppStorage("decoder.initialPrompt") private var initialPrompt: String = ""

    // Decoder options
    @AppStorage("decoder.suppressBlank") private var suppressBlank: Bool = true
    @AppStorage("decoder.temperatureFallbackCount") private var temperatureFallbackCount: Int = 5
    // Stored as Double via AppStorage; decoder reads as Float?; sentinel -999 = nil (use default)
    @AppStorage("decoder.compressionRatioThreshold") private var compressionRatioThreshold: Double = 2.4
    @AppStorage("decoder.logProbThreshold") private var logProbThreshold: Double = -1.0

    // Audio preprocessing
    @AppStorage("audio.preprocess.enabled") private var preprocessEnabled: Bool = true

    // Review before paste
    @AppStorage("review.beforePaste") private var reviewBeforePaste: Bool = false

    // Voice activity detection
    @AppStorage("vad.energyThresholdDBFS") private var vadEnergyThreshold: Double = -45.0
    @AppStorage("vad.energyVoicedRatio") private var vadEnergyRatio: Double = 0.30
    @AppStorage("vad.sileroVoicedRatio") private var vadSileroRatio: Double = 0.25

    @State private var decoderExpanded: Bool = false
    @State private var vadExpanded: Bool = false

    private let languages: [(label: String, code: String)] = [
        ("Auto-detect", ""),
        ("English", "en"),
        ("German", "de"),
        ("French", "fr"),
        ("Spanish", "es"),
        ("Italian", "it"),
        ("Portuguese", "pt"),
        ("Russian", "ru"),
        ("Ukrainian", "uk"),
        ("Polish", "pl"),
        ("Dutch", "nl"),
        ("Japanese", "ja"),
        ("Chinese", "zh"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(
                    title: "Transcription",
                    subtitle: "Language, prompt hints, decoder tuning, and audio processing."
                )

                // MARK: Language
                RowCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Language")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Force a specific language or let the model detect it.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $language) {
                                ForEach(languages, id: \.code) { lang in
                                    Text(lang.label).tag(lang.code)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }
                        .padding(18)
                    }
                }

                // MARK: Initial prompt / Vocabulary
                RowCard {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Initial prompt / Vocabulary")
                                .font(.system(size: 14, weight: .medium))
                            Text("Names, jargon, product terms — helps the model spell them correctly.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        TextEditor(text: $initialPrompt)
                            .font(.system(size: 13))
                            .frame(minHeight: 72, maxHeight: 88)
                            .scrollContentBackground(.hidden)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.primary.opacity(0.1))
                            )
                    }
                    .padding(18)
                }

                // MARK: Decoder options (Whisper only)
                RowCard {
                    VStack(alignment: .leading, spacing: 0) {
                        DisclosureGroup(isExpanded: $decoderExpanded) {
                            VStack(alignment: .leading, spacing: 0) {
                                Divider().opacity(0.5)

                                // Suppress blank
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Suppress blank output")
                                            .font(.system(size: 14, weight: .medium))
                                        Text("Discard segments that contain only whitespace.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $suppressBlank)
                                        .labelsHidden()
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)

                                Divider().opacity(0.5)

                                // Temperature fallbacks
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Temperature fallbacks")
                                            .font(.system(size: 14, weight: .medium))
                                        Text("Number of temperature increases on decoding failure (0–10).")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Stepper("\(temperatureFallbackCount)", value: $temperatureFallbackCount, in: 0...10)
                                        .fixedSize()
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)

                                Divider().opacity(0.5)

                                // Compression ratio threshold
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Compression ratio threshold")
                                            .font(.system(size: 14, weight: .medium))
                                        Spacer()
                                        Text(String(format: "%.1f", compressionRatioThreshold))
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: $compressionRatioThreshold, in: 1.0...5.0, step: 0.1)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)

                                Divider().opacity(0.5)

                                // Log-prob threshold
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Log-prob threshold")
                                            .font(.system(size: 14, weight: .medium))
                                        Spacer()
                                        Text(String(format: "%.1f", logProbThreshold))
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: $logProbThreshold, in: -5.0...0.0, step: 0.1)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)

                                Divider().opacity(0.5)

                                Text("Applies to Whisper models")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                            }
                        } label: {
                            Text("Decoder options (Whisper only)")
                                .font(.system(size: 14, weight: .medium))
                                .padding(18)
                        }
                    }
                }

                // MARK: Audio preprocessing
                RowCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Clean up mic audio")
                                    .font(.system(size: 14, weight: .medium))
                                Text("DC removal, high-pass filter, and auto gain control (AGC).")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $preprocessEnabled)
                                .labelsHidden()
                        }
                        .padding(18)
                    }
                }

                // MARK: Review before paste
                RowCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Review transcript before pasting")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Hold after transcription to confirm. ⌥Space to paste, Esc to cancel.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $reviewBeforePaste)
                                .labelsHidden()
                        }
                        .padding(18)
                    }
                }

                // MARK: Voice activity detection
                RowCard {
                    VStack(alignment: .leading, spacing: 0) {
                        DisclosureGroup(isExpanded: $vadExpanded) {
                            VStack(alignment: .leading, spacing: 0) {
                                Divider().opacity(0.5)

                                // Silero voiced ratio
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Silero voiced ratio")
                                                .font(.system(size: 14, weight: .medium))
                                            Text("Fraction of frames Silero must flag as voiced. Lower = more sensitive.")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(String(format: "%.2f", vadSileroRatio))
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: $vadSileroRatio, in: 0.05...0.8, step: 0.05)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)

                                Divider().opacity(0.5)

                                // Energy VAD threshold (fallback)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Energy threshold (fallback)")
                                                .font(.system(size: 14, weight: .medium))
                                            Text("dBFS level that counts as voiced if Silero is unavailable.")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(String(format: "%.0f dB", vadEnergyThreshold))
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: $vadEnergyThreshold, in: -70.0 ... -20.0, step: 1.0)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)

                                Divider().opacity(0.5)

                                // Energy VAD voiced ratio
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Energy voiced ratio (fallback)")
                                                .font(.system(size: 14, weight: .medium))
                                            Text("Fraction of RMS frames over threshold required for voiced.")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(String(format: "%.2f", vadEnergyRatio))
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: $vadEnergyRatio, in: 0.05...0.8, step: 0.05)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                            }
                        } label: {
                            Text("Voice activity detection")
                                .font(.system(size: 14, weight: .medium))
                                .padding(18)
                        }
                    }
                }
            }
            .padding(32)
        }
    }
}
