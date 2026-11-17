import AVFoundation
import Foundation
import MediaPlayer
import Observation
import OSLog
import UIKit

extension Notification.Name {
    static let liveListenWillStart = Notification.Name("voice-to-text-ai.liveListenWillStart")
}

enum PlaybackMemory {
    static let rateKey = "playbackRate"
    static let positionsKey = "playbackPositions"
    private static let orderKey = "playbackPositionsOrder"
    static let rateRange: ClosedRange<Double> = 0.5...5
    private static let positionCap = 200
    private static let resumeMargin: Double = 5

    static var rate: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: rateKey)
            return stored > 0 ? clampRate(stored) : 1
        }
        set { UserDefaults.standard.set(clampRate(newValue), forKey: rateKey) }
    }

    static func clampRate(_ value: Double) -> Double {
        min(max((value * 100).rounded() / 100, rateRange.lowerBound), rateRange.upperBound)
    }

    static func resumePosition(for id: UUID, duration: Double) -> Double? {
        guard let saved = positions[id.uuidString], saved > resumeMargin, saved < duration - resumeMargin else { return nil }
        return saved
    }

    static func record(_ seconds: Double, for id: UUID, duration: Double) {
        guard seconds > resumeMargin, seconds < duration - resumeMargin else { return forget(id) }
        let key = id.uuidString
        var saved = positions
        saved[key] = seconds
        var order = (UserDefaults.standard.stringArray(forKey: orderKey) ?? []).filter { $0 != key && saved[$0] != nil }
        let tracked = Set(order)
        order = saved.keys.filter { $0 != key && !tracked.contains($0) } + order + [key]
        while order.count > positionCap { saved[order.removeFirst()] = nil }
        UserDefaults.standard.set(saved, forKey: positionsKey)
        UserDefaults.standard.set(order, forKey: orderKey)
    }

    static func forget(_ id: UUID) {
        var saved = positions
        guard saved.removeValue(forKey: id.uuidString) != nil else { return }
        UserDefaults.standard.set(saved, forKey: positionsKey)
        let order = (UserDefaults.standard.stringArray(forKey: orderKey) ?? []).filter { $0 != id.uuidString }
        UserDefaults.standard.set(order, forKey: orderKey)
    }

    private static var positions: [String: Double] {
        (UserDefaults.standard.dictionary(forKey: positionsKey) ?? [:]).compactMapValues { $0 as? Double }
    }
}

extension RecordingPlayer.Source {
    init(_ entry: RecordingHistoryEntry, url: URL) {
        self.init(id: entry.id, url: url, title: RecordingDateFormat.rowLabel(entry.createdAt), duration: entry.durationSeconds)
    }
}

@Observable
final class RecordingPlayer {
    struct Source: Equatable {
        let id: UUID
        let url: URL
        let title: String
        let duration: Double
    }

    enum ScanDirection {
        case forward
        case backward
    }

    struct Scan: Equatable {
        let direction: ScanDirection
        var rate: Double
    }

    static let backInterval: Double = 15
    static let forwardInterval: Double = 30
    private static let scanRates: [Double] = [8, 16, 32]
    private static let lockScreenRates: [NSNumber] = [1, 1.25, 1.5, 2, 3, 5]

    private(set) var source: Source?
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var rate: Double = PlaybackMemory.rate
    private(set) var scan: Scan?
    private(set) var peaks: [Float]?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var commands: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var ownsNowPlaying = false
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private var scrubbing = false
    @ObservationIgnored private var seeking = false
    @ObservationIgnored private var queuedSeek: (seconds: Double, exact: Bool)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var starting: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanRestore: (playing: Bool, muted: Bool)?
    @ObservationIgnored private var peakTask: Task<Void, Never>?
    @ObservationIgnored private var lastScanTick: TimeInterval = 0

    var remaining: Double { max(0, duration - position) / rate }
    var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
    private var atEnd: Bool { duration > 0 && position >= duration - 0.05 }

    func load(_ source: Source) {
        if self.source == source, player != nil { return }
        if player != nil { stop() }
        generation += 1
        self.source = source
        rate = PlaybackMemory.rate
        duration = max(source.duration, 0)
        position = PlaybackMemory.resumePosition(for: source.id, duration: duration) ?? 0
        isPlaying = false
        scan = nil

        let asset = AVURLAsset(url: source.url)
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        player.defaultRate = Float(rate)
        self.player = player
        if position > 0 { seek(to: position, exact: true) }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10),
            queue: .main
        ) { @Sendable [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        observe(item)
        loadPeaks(source.url)

        let current = generation
        Task { [weak self] in
            guard let seconds = try? await asset.load(.duration).seconds, seconds.isFinite, seconds > 0 else { return }
            guard let self, self.generation == current else { return }
            self.duration = seconds
            self.position = min(self.position, seconds)
        }
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard player != nil, starting == nil else { return }
        let listener = MacRemote.shared.listener
        guard listener.isActive else { return startPlayback() }
        isPlaying = true
        starting = Task { [weak self] in
            await listener.stopAndWait()
            guard !Task.isCancelled, let self else { return }
            self.starting = nil
            self.startPlayback()
        }
    }

    func pause() {
        cancelStart()
        if scan != nil { finishScan(resume: false) }
        player?.pause()
        let wasPlaying = isPlaying
        isPlaying = false
        if wasPlaying { rememberPosition() }
        updateNowPlaying()
    }

    func stop() {
        guard player != nil else { return }
        cancelStart()
        if scan != nil { finishScan(resume: false) }
        player?.pause()
        isPlaying = false
        rememberPosition()
        releaseSystemControls()
        teardown()
        deactivateSession()
    }

    func skip(by seconds: Double) {
        guard player != nil else { return }
        seek(to: position + seconds, exact: true)
    }

    func seek(to seconds: Double) {
        seek(to: seconds, exact: true)
    }

    func beginScrub() {
        guard player != nil else { return }
        scrubbing = true
    }

    func scrub(to seconds: Double) {
        guard scrubbing else { return }
        seek(to: seconds, exact: false)
    }

    func endScrub(at seconds: Double) {
        guard scrubbing else { return }
        scrubbing = false
        seek(to: seconds, exact: true)
    }

    func setRate(_ value: Double) {
        let clamped = PlaybackMemory.clampRate(value)
        PlaybackMemory.rate = clamped
        guard clamped != rate else { return }
        rate = clamped
        player?.defaultRate = Float(clamped)
        if isPlaying, scan == nil, starting == nil { player?.rate = Float(clamped) }
        updateNowPlaying()
    }

    func beginScan(_ direction: ScanDirection) {
        guard let player, scan == nil else { return }
        if starting != nil {
            cancelStart()
            isPlaying = false
        }
        if direction == .forward, atEnd { return }
        scanRestore = (isPlaying, player.isMuted)
        scan = Scan(direction: direction, rate: Self.scanRates[0])
        switch direction {
        case .forward:
            activateSession()
            applyForwardScan()
        case .backward:
            player.pause()
            player.isMuted = true
        }
        let started = ContinuousClock.now
        scanTask = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                let now = ContinuousClock.now
                let held = now - started
                self.stepScan(level: held >= .seconds(3) ? 2 : held >= .milliseconds(1500) ? 1 : 0, elapsed: now - last)
                last = now
            }
        }
        updateNowPlaying()
    }

    func endScan() {
        guard scan != nil else { return }
        finishScan(resume: true)
        updateNowPlaying()
    }

    private func startPlayback() {
        guard let player else { return }
        activateSession()
        if atEnd { seek(to: 0, exact: true) }
        player.defaultRate = Float(rate)
        player.play()
        isPlaying = true
        claimSystemControls()
        updateNowPlaying()
    }

    private func cancelStart() {
        starting?.cancel()
        starting = nil
    }

    private func tick(_ time: CMTime) {
        guard let player else { return }
        if !scrubbing, !seeking, scan?.direction != .backward {
            let now = ProcessInfo.processInfo.systemUptime
            let seconds = time.seconds
            if seconds.isFinite, scan == nil || now - lastScanTick >= 1.0 / 30 {
                lastScanTick = now
                position = min(max(seconds, 0), duration)
            }
        }
        if isPlaying, scan == nil, starting == nil, !seeking, player.rate == 0 {
            isPlaying = false
            rememberPosition()
            updateNowPlaying()
        }
    }

    private func finished() {
        if scan != nil { finishScan(resume: false) }
        isPlaying = false
        position = duration
        if let source { PlaybackMemory.forget(source.id) }
        updateNowPlaying()
    }

    private func seek(to seconds: Double, exact: Bool) {
        let target = min(max(seconds, 0), duration)
        position = target
        guard let player else { return }
        if seeking {
            queuedSeek = (target, exact)
            return
        }
        seeking = true
        let tolerance = exact ? CMTime.zero : CMTime(value: 1, timescale: 4)
        let current = generation
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.seekFinished(current) }
        }
    }

    private func seekFinished(_ current: Int) {
        guard current == generation else { return }
        seeking = false
        if let next = queuedSeek {
            queuedSeek = nil
            seek(to: next.seconds, exact: next.exact)
        } else {
            updateNowPlaying()
        }
    }

    private func stepScan(level: Int, elapsed: Duration) {
        guard var scan, player != nil else { return }
        let target = Self.scanRates[min(level, Self.scanRates.count - 1)]
        if target != scan.rate {
            scan.rate = target
            self.scan = scan
            if scan.direction == .forward {
                applyForwardScan()
                updateNowPlaying()
            }
        }
        guard scan.direction == .backward, position > 0 else { return }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        seek(to: position - scan.rate * seconds, exact: false)
    }

    private func applyForwardScan() {
        guard let scan, let player else { return }
        player.isMuted = scan.rate > Self.scanRates[0] || scanRestore?.muted == true
        player.rate = Float(scan.rate)
    }

    private func finishScan(resume: Bool) {
        let direction = scan?.direction
        let restore = scanRestore
        scanTask?.cancel()
        scanTask = nil
        scan = nil
        scanRestore = nil
        guard let player else { return }
        player.isMuted = restore?.muted ?? false
        if resume, restore?.playing == true, !atEnd {
            player.rate = Float(rate)
            isPlaying = true
        } else {
            player.pause()
            if resume, restore?.playing == true { isPlaying = false }
            if direction == .backward { seek(to: position, exact: true) }
        }
    }

    private func rememberPosition() {
        guard let source else { return }
        if atEnd { return PlaybackMemory.forget(source.id) }
        PlaybackMemory.record(position, for: source.id, duration: duration)
    }

    private func loadPeaks(_ url: URL) {
        peakTask?.cancel()
        if let cached = WaveformStore.cached(url) {
            peaks = cached
            return
        }
        peaks = nil
        let current = generation
        peakTask = Task { [weak self] in
            let result = await WaveformStore.peaks(for: url)
            guard !Task.isCancelled, let self, self.generation == current else { return }
            self.peaks = result
        }
    }

    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            sessionActive = true
        } catch {
            AppLog.audio.error("Playback couldn't start audio: \(String(describing: error), privacy: .public)")
        }
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        sessionActive = false
        guard !MacRemote.shared.listener.isActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observe(_ item: AVPlayerItem) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated { self?.finished() }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { @Sendable [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated {
                guard let self, self.isPlaying || self.scan != nil else { return }
                self.pause()
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { @Sendable [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.pause()
            }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated {
                self?.rememberPosition()
                self?.updateNowPlaying()
            }
        })
        observers.append(center.addObserver(
            forName: .liveListenWillStart,
            object: nil,
            queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated { self?.yieldToLiveListen() }
        })
    }

    private func yieldToLiveListen() {
        guard player != nil else { return }
        pause()
        releaseSystemControls()
        sessionActive = false
    }

    private func teardown() {
        generation += 1
        peakTask?.cancel()
        peakTask = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
        seeking = false
        queuedSeek = nil
        scrubbing = false
    }

    private func claimSystemControls() {
        ownsNowPlaying = true
        guard commands.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { $0.play() }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { $0.toggle() }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.forwardInterval)]
        register(center.skipForwardCommand) { $0.skip(by: Self.forwardInterval) }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.backInterval)]
        register(center.skipBackwardCommand) { $0.skip(by: -Self.backInterval) }
        center.changePlaybackRateCommand.supportedPlaybackRates = Self.lockScreenRates
        center.changePlaybackRateCommand.isEnabled = true
        commands.append((center.changePlaybackRateCommand, center.changePlaybackRateCommand.addTarget { @Sendable [weak self] event in
            guard let rate = (event as? MPChangePlaybackRateCommandEvent)?.playbackRate else { return .commandFailed }
            Task { @MainActor [weak self] in self?.setRate(Double(rate)) }
            return .success
        }))
        center.changePlaybackPositionCommand.isEnabled = true
        commands.append((center.changePlaybackPositionCommand, center.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
            guard let time = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: time) }
            return .success
        }))
    }

    private func register(_ command: MPRemoteCommand, _ action: @escaping @MainActor @Sendable (RecordingPlayer) -> Void) {
        command.isEnabled = true
        let token = command.addTarget { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                action(self)
            }
            return .success
        }
        commands.append((command, token))
    }

    private func releaseSystemControls() {
        let center = MPRemoteCommandCenter.shared()
        for (command, token) in commands {
            command.removeTarget(token)
            if command !== center.pauseCommand, command !== center.togglePlayPauseCommand {
                command.isEnabled = false
            }
        }
        commands = []
        if ownsNowPlaying {
            ownsNowPlaying = false
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    private func updateNowPlaying() {
        guard ownsNowPlaying, let source else { return }
        let playing: Double
        if let scan {
            playing = scan.direction == .forward ? scan.rate : 0
        } else {
            playing = isPlaying ? rate : 0
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: source.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }
}
