import Foundation

/// Which local preparations can be cancelled, and which cancelled ones are
/// still draining: their SDK call hasn't returned yet, so files may still land.
nonisolated struct ModelDownloadLedger: Equatable, Sendable {
    private(set) var downloading: Set<String> = []
    private(set) var cancelled: Set<String> = []
    private var draining: [String: Int] = [:]
    private var cancels: [String: Int] = [:]
    /// The dictation model, when the user cancelled its download. The launch
    /// download leaves it alone until the user asks for it again — a
    /// Download, a dictation that needs it — or picks another dictation
    /// model. The registry keeps it across launches.
    private(set) var launchSkippedID: String?

    init(launchSkippedID: String? = nil) {
        self.launchSkippedID = launchSkippedID
    }

    var drainingIDs: [String] { draining.keys.sorted() }

    /// `isDownload` is false for a model already on disk whole, which only
    /// loads: removing its files would delete a working model.
    mutating func began(_ id: String, isDownload: Bool) {
        cancelled.remove(id)
        if launchSkippedID == id { launchSkippedID = nil }
        if isDownload { downloading.insert(id) } else { downloading.remove(id) }
    }

    mutating func dictationModelChanged(to id: String) {
        if launchSkippedID != id { launchSkippedID = nil }
    }

    func skipsLaunchDownload(of id: String) -> Bool {
        launchSkippedID == id
    }

    /// How many of `id`'s downloads the user has cancelled. A caller that
    /// waited on a preparation compares it with the count from before: a
    /// cancel and a new Download can both land within the wait, and the new
    /// one clears `wasCancelled`.
    func cancelCount(_ id: String) -> Int {
        cancels[id] ?? 0
    }

    mutating func ended(_ id: String) {
        downloading.remove(id)
    }

    func canCancel(_ id: String) -> Bool {
        downloading.contains(id)
    }

    @discardableResult
    mutating func cancel(_ id: String, isDictationModel: Bool = false) -> Bool {
        guard downloading.remove(id) != nil else { return false }
        cancelled.insert(id)
        draining[id, default: 0] += 1
        cancels[id, default: 0] += 1
        if isDictationModel { launchSkippedID = id }
        return true
    }

    func wasCancelled(_ id: String) -> Bool {
        cancelled.contains(id)
    }

    func isDraining(_ id: String) -> Bool {
        draining[id] != nil
    }

    mutating func drained(_ id: String) {
        guard let count = draining[id] else { return }
        draining[id] = count > 1 ? count - 1 : nil
    }
}
