import Foundation

/// The audio of a `startStream` take, as its client sends it. `audio` requests
/// land here straight from the API's serial queue: the main-actor tasks every
/// other request runs in promise no order, and the words of a take depend on
/// its samples staying in the order they were spoken.
nonisolated final class ExternalAudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var connectionID: UInt64?
    private var preprocessor = AudioPreprocessor()
    private var samples: [Float] = []
    private var onChunk: (@Sendable ([Float]) -> Void)?

    /// Takes audio from `connection` until `close`. `onChunk` gets each piece
    /// for a live model, in order.
    func open(for connection: ExternalAPIConnection, onChunk: (@Sendable ([Float]) -> Void)?) {
        lock.withLock {
            connectionID = connection.id
            preprocessor.reset()
            samples = []
            self.onChunk = onChunk
        }
    }

    /// Audio from anyone but the take's client, or outside a take, is dropped.
    func append(_ pcm: String?, from connection: ExternalAPIConnection) {
        guard let pcm, var piece = ExternalAPI.samples(fromPCM: pcm) else { return }
        lock.withLock {
            guard connectionID == connection.id else { return }
            // What the recorder does to the microphone's samples, so a model
            // hears the same thing from either.
            if AudioPreprocessor.isEnabled { preprocessor.process(&piece) }
            AudioPreprocessor.clampToFullScale(&piece)
            samples.append(contentsOf: piece)
            onChunk?(piece)
        }
    }

    /// Ends the take's audio and hands over everything it sent.
    func close() -> [Float] {
        lock.withLock {
            connectionID = nil
            onChunk = nil
            defer { samples = [] }
            return samples
        }
    }
}
