#if arch(x86_64)
import AVFoundation
import Foundation

/// The Intel slice's other uses of the app's executable, which `AppEntry`
/// checks before the app starts.
nonisolated enum TranscribeWorkerEntry {
    /// Runs the worker — or, in a Debug build, the self-test — when the
    /// arguments ask for it, and exits when it's done. Returns otherwise.
    static func runIfRequested(arguments: [String]) {
        guard arguments.count > 1 else { return }
        switch arguments[1] {
        case TranscribeWorkerProtocol.workerFlag:
            exit(TranscribeWorker.run(cpuOnly: arguments.dropFirst(2).contains(TranscribeWorkerProtocol.cpuOnlyFlag)))
        #if DEBUG
        case TranscribeSelfTest.flag:
            TranscribeSelfTest.run(arguments: Array(arguments.dropFirst(2)))
        case TranscribeSelfTest.fetchFlag:
            TranscribeSelfTest.fetch(catalogIDs: Array(arguments.dropFirst(2)))
        #endif
        default:
            return
        }
    }
}

#if DEBUG
/// Debug builds only: drives the real `TranscribeSupervisor` from the command
/// line, without the app — start a worker, load a model, transcribe a file —
/// and prints where it ran, how long it took and what it heard.
///
///     VoiceToText --transcribe-selftest <model path or catalog id> <audio file> [runs]
///     VoiceToText --transcribe-fetch <catalog id>…
///
/// `--transcribe-fetch` downloads models the way the app does — pinned URL,
/// size and SHA-256 (`TranscribeCppDownload`) — into `TranscribeCppModel`'s
/// folder (`VTT_TRANSCRIBE_MODELS_DIR` in a test), and re-hashes any already
/// there, so a cached copy is held to the same pins.
///
/// The GPU preference is the build's own `UserDefaults`, as in the app, so a
/// GPU failure it records makes the next run start CPU-only. With
/// `VTT_WORKER_FAULT` set, the worker it starts simulates a bad GPU driver.
nonisolated enum TranscribeSelfTest {
    static let flag = "--transcribe-selftest"
    static let fetchFlag = "--transcribe-fetch"

    static func fetch(catalogIDs: [String]) -> Never {
        guard !catalogIDs.isEmpty else {
            print("usage: VoiceToText \(fetchFlag) <catalog id>…")
            exit(64)
        }
        Task.detached {
            do {
                for id in catalogIDs {
                    guard let model = TranscribeCppModel.model(forCatalogID: id) else {
                        throw SelfTestError("there is no transcribe.cpp build of \(id)")
                    }
                    let clock = ContinuousClock.now
                    if model.isDownloaded() {
                        guard try TranscribeCppDownload.sha256Hex(of: model.fileURL) == model.sha256 else {
                            try? FileManager.default.removeItem(at: model.fileURL)
                            throw SelfTestError("\(model.fileName) on disk didn't match its checksum; removed it")
                        }
                        print("\(id): already downloaded, checksum verified (\(milliseconds(since: clock)) ms)")
                    } else {
                        print("\(id): downloading \(model.downloadURL.absoluteString)")
                        try await TranscribeCppDownload.fetch(model, progress: nil)
                        print("\(id): downloaded and verified in \(milliseconds(since: clock)) ms")
                    }
                    print("\(id): \(model.fileURL.path) \(model.byteCount) bytes sha256 \(model.sha256)")
                }
                exit(0)
            } catch {
                print("FAILED: \(error.localizedDescription)")
                exit(1)
            }
        }
        dispatchMain()
    }

    static func run(arguments: [String]) -> Never {
        guard arguments.count >= 2 else {
            print("usage: VoiceToText \(flag) <model path or catalog id> <audio file> [runs]")
            exit(64)
        }
        let runs = arguments.count > 2 ? max(1, Int(arguments[2]) ?? 1) : 1
        Task.detached {
            do {
                try await selfTest(model: arguments[0], audio: URL(fileURLWithPath: arguments[1]), runs: runs)
                exit(0)
            } catch {
                print("FAILED: \(error.localizedDescription)")
                exit(1)
            }
        }
        dispatchMain()
    }

    private static func selfTest(model: String, audio: URL, runs: Int) async throws {
        let path: String
        let label: String
        if let catalogModel = TranscribeCppModel.model(forCatalogID: model) {
            guard catalogModel.isDownloaded() else {
                throw SelfTestError("\(model) isn't downloaded to \(catalogModel.fileURL.path)")
            }
            path = catalogModel.fileURL.path
            label = model
        } else {
            path = model
            label = (model as NSString).lastPathComponent
        }
        let samples = try loadAudio(audio)
        print("audio: \(audio.lastPathComponent), \(String(format: "%.2f", Double(samples.count) / 16_000)) s")
        print("gpu preference: useGPU=\(TranscribeGPUPreference.useGPU) gpuFailed=\(TranscribeGPUPreference.gpuFailed)")
        print("threads: \(TranscribeSupervisor.threadCount)")

        let supervisor = TranscribeSupervisor(label: label)
        var clock = ContinuousClock.now
        let loaded = try await supervisor.load(modelPath: path)
        let isCPUOnly = await supervisor.isCPUOnly ?? false
        print("load: \(milliseconds(since: clock)) ms (library \(Int(loaded.loadMilliseconds)) ms) worker=\(isCPUOnly ? "cpu-only" : "gpu-allowed") pid=\(await supervisor.workerPID.map(String.init) ?? "none")")
        print("device: \(loaded.device) backend=\(loaded.backend) onGPU=\(loaded.onGPU) arch=\(loaded.architecture)")
        for device in await supervisor.devices {
            print("registered: \(device.kind) \(device.description) gpu=\(device.isGPU)")
        }

        let isWhisper = loaded.architecture == "whisper"
        let options = isWhisper
            ? WhisperRunOptions.make(TranscriptionDecoderOptions.current, contextPrompt: nil, sampleCount: samples.count)
            : TranscribeSupervisor.RunOptions(withoutTimestamps: true)

        // `VTT_SELFTEST_CANCEL_AFTER_MS`: first cancel a transcription that
        // far in, as the app does when the user cancels.
        if let raw = ProcessInfo.processInfo.environment["VTT_SELFTEST_CANCEL_AFTER_MS"], let delay = Int(raw) {
            clock = ContinuousClock.now
            let cancelled = Task { try await supervisor.transcribe(samples, options: options) }
            try await Task.sleep(for: .milliseconds(delay))
            cancelled.cancel()
            switch await cancelled.result {
            case .success:
                print("cancel: finished before the cancel landed, \(milliseconds(since: clock)) ms")
            case .failure(let error):
                print("cancel: \(error is CancellationError ? "cancelled" : "failed: \(error.localizedDescription)") after \(milliseconds(since: clock)) ms; worker pid=\(await supervisor.workerPID.map(String.init) ?? "none")")
            }
        }

        for run in 1...runs {
            clock = ContinuousClock.now
            let transcript = try await supervisor.transcribe(samples, options: options)
            let after = await supervisor.loaded
            print("run \(run): \(milliseconds(since: clock)) ms (mel \(Int(transcript.melMilliseconds)), encode \(Int(transcript.encodeMilliseconds)), decode \(Int(transcript.decodeMilliseconds))) device=\(after?.device ?? "?") backend=\(after?.backend ?? "?") worker=\(await supervisor.isCPUOnly == true ? "cpu-only" : "gpu-allowed") pid=\(await supervisor.workerPID.map(String.init) ?? "none") language=\(transcript.language ?? "-")")
            print("text: \(transcript.text)")
        }
        print("gpu preference after: useGPU=\(TranscribeGPUPreference.useGPU) gpuFailed=\(TranscribeGPUPreference.gpuFailed)")
        await supervisor.unload()
    }

    /// The file as 16 kHz mono Float32, whatever it was recorded as.
    private static func loadAudio(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SelfTestError("can't read \(url.lastPathComponent)")
        }
        try file.read(into: input)
        let capacity = AVAudioFrameCount(Double(input.frameLength) * 16_000 / file.processingFormat.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw SelfTestError("can't convert \(url.lastPathComponent)")
        }
        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let conversionError { throw conversionError }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = start.duration(to: .now)
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    private struct SelfTestError: LocalizedError {
        let errorDescription: String?

        init(_ message: String) { errorDescription = message }
    }
}
#endif
#endif
