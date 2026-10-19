import AVFoundation
import CoreML
import FluidAudio
import Foundation

// pbench download <modelDir>
//   Downloads the Parakeet TDT 0.6B v3 CoreML models with FluidAudio into <modelDir>
//   (its last path component must be "parakeet-tdt-0.6b-v3").
// pbench run <modelDir> <audio.wav> <cpu|ane|gpu|all> <textOut> [warmRuns]
//   Loads the models, runs one cold full-length transcription, then warmRuns warm ones,
//   writes the last transcript to textOut and prints one RESULT line.

func loadSamples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

#if arch(x86_64)
let archName = "x86_64"
#else
let archName = "arm64"
#endif

let args = CommandLine.arguments
guard args.count >= 3 else { fail("usage: pbench download <modelDir> | pbench run <modelDir> <wav> <units> <textOut> [warmRuns]") }

switch args[1] {
case "download":
    let dir = URL(fileURLWithPath: args[2])
    let start = Date()
    let path = try await AsrModels.download(to: dir, version: .v3)
    print(String(format: "DOWNLOADED %@ in %.1fs", path.path, Date().timeIntervalSince(start)))

case "run":
    guard args.count >= 6 else { fail("usage: pbench run <modelDir> <wav> <units> <textOut> [warmRuns]") }
    let modelDir = URL(fileURLWithPath: args[2])
    let audio = try loadSamples(URL(fileURLWithPath: args[3]))
    let unitsName = args[4]
    let textOut = URL(fileURLWithPath: args[5])
    let warmRuns = args.count > 6 ? (Int(args[6]) ?? 3) : 3
    let units: MLComputeUnits = switch unitsName {
    case "cpu": .cpuOnly
    case "gpu": .cpuAndGPU
    case "all": .all
    default: .cpuAndNeuralEngine
    }

    let config = MLModelConfiguration()
    config.computeUnits = units

    let loadStart = Date()
    let models = try await AsrModels.load(from: modelDir, configuration: config, version: .v3)
    let manager = AsrManager(models: models)
    let loadSeconds = Date().timeIntervalSince(loadStart)

    func transcribe(_ samples: [Float]) async throws -> String {
        var state = try TdtDecoderState()
        return try await manager.transcribe(samples, decoderState: &state).text
    }

    let coldStart = Date()
    var text = try await transcribe(audio)
    let cold = Date().timeIntervalSince(coldStart)

    var times: [Double] = []
    for _ in 0..<warmRuns {
        let start = Date()
        text = try await transcribe(audio)
        times.append(Date().timeIntervalSince(start))
    }
    try text.write(to: textOut, atomically: true, encoding: .utf8)
    let audioSeconds = Double(audio.count) / 16000
    let mean = times.isEmpty ? cold : times.reduce(0, +) / Double(times.count)
    print(String(format: "RESULT arch=%@ units=%@ audio=%.3f load=%.3f cold=%.3f warm=%@ warm_mean=%.3f rtfx_warm=%.2f",
                 archName, unitsName, audioSeconds, loadSeconds, cold,
                 times.isEmpty ? "-" : times.map { String(format: "%.3f", $0) }.joined(separator: ","), mean,
                 audioSeconds / mean))

default:
    fail("unknown mode \(args[1])")
}
