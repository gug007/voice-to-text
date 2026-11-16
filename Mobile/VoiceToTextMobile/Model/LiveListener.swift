import AVFoundation
import Foundation
import MediaPlayer
import Observation
import OSLog

@Observable
final class LiveListener {
    enum State: Equatable {
        case off
        case connecting
        case listening
        case reconnecting
        case failed(String)
    }

    private(set) var state: State = .off
    private(set) var linkID: String?

    @ObservationIgnored var onEnd: (() -> Void)?
    @ObservationIgnored private weak var link: MacLink?
    @ObservationIgnored private var run: Task<Void, Never>?
    @ObservationIgnored private var reader: Task<LiveStreamReader.Outcome, Never>?
    @ObservationIgnored private var output: LiveAudioOutput?
    @ObservationIgnored private var teardown: Task<Void, Never>?
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var commands: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var connection = 0

    private static let retryDelays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2)]

    var isActive: Bool {
        switch state {
        case .connecting, .listening, .reconnecting: return true
        case .off, .failed: return false
        }
    }

    func state(for link: MacLink) -> State {
        linkID == link.id ? state : .off
    }

    func start(_ link: MacLink) {
        end(.off)
        generation += 1
        let current = generation
        self.link = link
        linkID = link.id
        state = .connecting
        run = Task { await listen(current) }
    }

    func stop() {
        end(.off)
    }

    func stopAndWait() async {
        end(.off)
        await teardown?.value
    }

    func clear(linkID id: String) {
        guard linkID == id else { return }
        end(.off)
    }

    private func listen(_ current: Int) async {
        await teardown?.value
        guard current == generation, let link else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            sessionActive = true
        } catch {
            AppLog.remote.error("Live listen couldn't start audio: \(String(describing: error), privacy: .public)")
            return end(.failed("This iPhone couldn't start playing audio."))
        }
        let output = LiveAudioOutput { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event, current) }
        }
        self.output = output
        installSystemHooks(macName: link.macName)

        var attempts = 0
        var heardAny = false
        while current == generation {
            connection += 1
            let attempt = connection
            let outcome: LiveStreamReader.Outcome
            do {
                let (session, request) = try await link.liveAudioRequest()
                guard current == generation else { return }
                let heard: @Sendable () -> Void = { [weak self] in
                    Task { @MainActor [weak self] in self?.audioArrived(current, attempt) }
                }
                let reader = Task.detached { await LiveStreamReader.read(request, session: session, into: output, onAudio: heard) }
                self.reader = reader
                outcome = await reader.value
            } catch {
                outcome = .failed(error, heardAudio: false)
            }
            connection += 1
            guard current == generation else { return }
            let stillRecording = link.status?.state == .recording
            let problem: String
            switch outcome {
            case .ended(let heard):
                heardAny = heardAny || heard
                AppLog.remote.notice("Live stream from \(link.macName, privacy: .public) ended (audio: \(heard), recording: \(stillRecording))")
                guard stillRecording else { return end(.off) }
                if heard {
                    attempts = 0
                    continue
                }
                problem = "No audio from the Mac."
            case .refused(let status, let message):
                AppLog.remote.notice("Live stream from \(link.macName, privacy: .public) refused: \(status)")
                if status == 409, heardAny { return end(.off) }
                guard status == 503, heardAny, stillRecording else { return end(.failed(message ?? Self.refusal(status))) }
                problem = message ?? Self.refusal(status)
            case .unreadable:
                return end(.failed(MacRemoteError.badReply.errorDescription ?? "The Mac sent audio this iPhone can't play."))
            case .failed(let error, let heard):
                heardAny = heardAny || heard
                AppLog.remote.notice("Live stream from \(link.macName, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                guard stillRecording else { return end(.off) }
                if heard { attempts = 0 }
                problem = Self.lost(error)
            }
            attempts += 1
            guard attempts <= Self.retryDelays.count else { return end(.failed(problem)) }
            state = .reconnecting
            try? await Task.sleep(for: Self.retryDelays[attempts - 1])
        }
    }

    private func audioArrived(_ current: Int, _ attempt: Int) {
        guard current == generation, attempt == connection, state != .listening else { return }
        state = .listening
        AppLog.remote.notice("Live listening to \(self.link?.macName ?? "Mac", privacy: .public)")
    }

    private func handle(_ event: LiveAudioOutput.Event, _ current: Int) {
        guard current == generation else { return }
        switch event {
        case .failed(let message):
            end(.failed(message))
        }
    }

    private static func lost(_ error: Error) -> String {
        switch (error as? URLError)?.code {
        case .timedOut:
            return "No audio from the Mac."
        case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet:
            return "Connection lost."
        default:
            return MacRemote.message(for: error)
        }
    }

    private static func refusal(_ status: Int) -> String {
        switch status {
        case 403: return "Listening from iPhone is turned off on this Mac."
        case 404: return "Update Voice to Text on the Mac to listen live."
        case 409: return "The Mac isn't recording right now."
        case 503: return "Two iPhones are already listening to this Mac."
        default: return "The Mac answered with an error (\(status))."
        }
    }

    private func end(_ final: State) {
        let wasActive = isActive
        generation += 1
        run?.cancel()
        run = nil
        reader?.cancel()
        reader = nil
        releaseSystemHooks()
        let output = self.output
        self.output = nil
        let deactivate = sessionActive
        sessionActive = false
        if output != nil || deactivate {
            let previous = teardown
            teardown = Task {
                await previous?.value
                await output?.shutdown()
                if deactivate {
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            }
        }
        if wasActive, case .failed(let message) = final {
            AppLog.remote.notice("Live listening failed: \(message, privacy: .public)")
        }
        state = final
        link = nil
        if final == .off { linkID = nil }
        if wasActive { onEnd?() }
    }

    private func installSystemHooks(macName: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "\(macName), live",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        let center = MPRemoteCommandCenter.shared()
        for command in [center.pauseCommand, center.stopCommand, center.togglePlayPauseCommand] {
            command.isEnabled = true
            let token = command.addTarget { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in self?.stop() }
                return .success
            }
            commands.append((command, token))
        }
        let notifications = NotificationCenter.default
        observers.append(notifications.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.stop() }
        })
        observers.append(notifications.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor [weak self] in self?.stop() }
        })
    }

    private func releaseSystemHooks() {
        for (command, token) in commands { command.removeTarget(token) }
        commands = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

nonisolated enum LiveStreamReader {
    enum Outcome: Sendable {
        case ended(heardAudio: Bool)
        case refused(Int, String?)
        case unreadable
        case failed(any Error, heardAudio: Bool)
    }

    private enum Expecting {
        case header
        case frameHeader
        case payload
    }

    static func read(
        _ request: URLRequest,
        session: URLSession,
        into output: LiveAudioOutput,
        onAudio: @escaping @Sendable () -> Void
    ) async -> Outcome {
        var heard = false
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { return .unreadable }
            guard http.statusCode == 200 else {
                var body = Data()
                for try await byte in bytes {
                    body.append(byte)
                    if body.count > 4096 { break }
                }
                let message = try? RemoteProtocol.makeDecoder().decode(RemoteErrorBody.self, from: body).error
                return .refused(http.statusCode, message)
            }
            var parser = LiveAudioStreamParser()
            var chunk: [UInt8] = []
            chunk.reserveCapacity(LiveAudioWire.maxPayload)
            var expecting = Expecting.header
            var need = LiveAudioWire.headerLength
            for try await byte in bytes {
                chunk.append(byte)
                guard chunk.count == need else { continue }
                let frames = try parser.append(Data(chunk))
                switch expecting {
                case .header:
                    guard let header = parser.header else { return .unreadable }
                    output.begin(header)
                    expecting = .frameHeader
                    need = LiveAudioWire.frameHeaderLength
                case .frameHeader:
                    let length = Int(chunk[4]) << 8 | Int(chunk[5])
                    if length > 0 {
                        expecting = .payload
                        need = length
                    }
                case .payload:
                    expecting = .frameHeader
                    need = LiveAudioWire.frameHeaderLength
                }
                chunk.removeAll(keepingCapacity: true)
                if !frames.isEmpty {
                    if !heard {
                        heard = true
                        onAudio()
                    }
                    output.receive(frames)
                }
            }
            return .ended(heardAudio: heard)
        } catch is LiveAudioStreamParser.Failure {
            return .unreadable
        } catch {
            return .failed(error, heardAudio: heard)
        }
    }
}

nonisolated final class LiveAudioOutput: @unchecked Sendable {
    enum Event: Sendable {
        case failed(String)
    }

    private let queue = DispatchQueue(label: "voice-to-text-ai.live-audio", qos: .userInitiated)
    private let events: @Sendable (Event) -> Void
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var decoder: LiveAudioDecoder?
    private var observer: NSObjectProtocol?
    private var pending: [AVAudioPCMBuffer] = []
    private var pendingFrames: Int64 = 0
    private var queuedFrames: Int64 = 0
    private var isPlaying = false
    private var generation = 0
    private var closed = false
    private var startFrames: Int64 = 0
    private var maxQueuedFrames: Int64 = 0
    private var decoded = 0
    private var underruns = 0
    private var drops = 0
    private var lastArrival: UInt64 = 0

    private static let liveCadence: UInt64 = 20_000_000

    init(events: @escaping @Sendable (Event) -> Void) {
        self.events = events
    }

    func begin(_ header: LiveAudioStreamHeader) {
        queue.async { self.open(header) }
    }

    func receive(_ frames: [LiveAudioFrame]) {
        queue.async { self.play(frames) }
    }

    func shutdown() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.close()
                continuation.resume()
            }
        }
    }

    private func open(_ header: LiveAudioStreamHeader) {
        guard !closed else { return }
        do {
            let decoder = try LiveAudioDecoder(header: header)
            self.decoder = decoder
            if engine == nil || format != decoder.output {
                try makeEngine(decoder.output)
            }
        } catch {
            AppLog.remote.error("Live audio couldn't start: \(String(describing: error), privacy: .public)")
            decoder = nil
            events(.failed("This iPhone couldn't play the Mac's audio."))
        }
    }

    private func makeEngine(_ format: AVAudioFormat) throws {
        stopEngine()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugRemoteListenMuted") { engine.mainMixerNode.outputVolume = 0 }
        #endif
        engine.prepare()
        try engine.start()
        self.engine = engine
        self.player = player
        self.format = format
        startFrames = Int64(format.sampleRate * 0.4)
        maxQueuedFrames = Int64(format.sampleRate * 2.0)
        resetQueue()
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.restart() }
        }
    }

    private func restart() {
        guard !closed, let engine, let player else { return }
        resetQueue()
        player.stop()
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            AppLog.remote.error("Live audio couldn't restart: \(String(describing: error), privacy: .public)")
            events(.failed("The iPhone's audio output changed."))
        }
    }

    private func play(_ frames: [LiveAudioFrame]) {
        guard !closed, let decoder, player != nil else { return }
        for frame in frames {
            do {
                guard let buffer = try decoder.decode(frame) else { continue }
                enqueue(buffer)
                decoded += 1
                #if DEBUG
                if decoded % 78 == 1 { logStats(buffer) }
                #endif
            } catch {
                AppLog.remote.debug("Live audio packet \(frame.sequence) didn't decode: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard let player else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let gap = now - min(lastArrival, now)
        lastArrival = now
        let frames = Int64(buffer.frameLength)
        if isPlaying {
            guard queuedFrames + frames > maxQueuedFrames else { return schedule(buffer, on: player) }
            drops += 1
            resetQueue()
            player.stop()
        }
        pending.append(buffer)
        pendingFrames += frames
        while let first = pending.first, pendingFrames - Int64(first.frameLength) >= startFrames {
            pending.removeFirst()
            pendingFrames -= Int64(first.frameLength)
        }
        guard pendingFrames >= startFrames, gap >= Self.liveCadence else { return }
        pending.forEach { schedule($0, on: player) }
        pending = []
        pendingFrames = 0
        isPlaying = true
        if !player.isPlaying { player.play() }
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, on player: AVAudioPlayerNode) {
        let frames = Int64(buffer.frameLength)
        let current = generation
        queuedFrames += frames
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.queue.async { self?.played(frames, current) }
        }
    }

    private func played(_ frames: Int64, _ current: Int) {
        guard current == generation else { return }
        queuedFrames -= frames
        if queuedFrames <= 0, isPlaying {
            queuedFrames = 0
            isPlaying = false
            underruns += 1
        }
    }

    private func resetQueue() {
        generation += 1
        queuedFrames = 0
        pending = []
        pendingFrames = 0
        isPlaying = false
    }

    #if DEBUG
    private func logStats(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let rate = format?.sampleRate ?? 16_000
        AppLog.remote.notice("Live audio: \(self.decoded) packets decoded, \(String(format: "%.2f", Double(self.queuedFrames) / rate)) s queued, \(self.underruns) underruns, \(self.drops) drops, rms \(String(format: "%.3f", rms))")
    }
    #endif

    private func stopEngine() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        format = nil
    }

    private func close() {
        closed = true
        resetQueue()
        stopEngine()
        decoder = nil
    }
}
