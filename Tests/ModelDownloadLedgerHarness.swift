import Foundation

struct ModelDownloadLedgerHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw ModelDownloadLedgerHarnessFailure(description: message)
    }
}

@main
struct ModelDownloadLedgerHarness {
    static func main() throws {
        try onlyADownloadCanBeCancelled()
        try aCancelIsRememberedUntilTheNextStart()
        try twoDownloadsCancelIndependently()
        try drainsAreCountedPerCancel()
        try aFinishedDownloadCannotBeCancelled()
        try aCancelledDownloadIsNotRestartedAtLaunch()
        try aCancelThenDownloadStillCountsTheCancel()
        print("Model download ledger harness passed")
    }

    /// Review: cancelling the dictation model's download, then relaunching,
    /// started the same download again unasked.
    private static func aCancelledDownloadIsNotRestartedAtLaunch() throws {
        var ledger = ModelDownloadLedger()
        ledger.began("parakeet-tdt-v3", isDownload: false)
        ledger.cancel("parakeet-tdt-v3", isDictationModel: true)
        try expect(!ledger.skipsLaunchDownload(of: "parakeet-tdt-v3"), "a refused cancel holds nothing back")

        ledger.began("parakeet-tdt-v3", isDownload: true)
        ledger.cancel("parakeet-tdt-v3", isDictationModel: true)
        try expect(ledger.skipsLaunchDownload(of: "parakeet-tdt-v3"), "a cancelled download waits to be asked for")
        try expect(!ledger.skipsLaunchDownload(of: "whisper-small"), "only that model")

        var another = ledger
        another.began("whisper-small", isDownload: true)
        another.cancel("whisper-small")
        try expect(another.skipsLaunchDownload(of: "parakeet-tdt-v3"), "cancelling another model's download keeps the hold")
        try expect(!another.skipsLaunchDownload(of: "whisper-small"), "and the launch never downloads that one anyway")

        let relaunched = ModelDownloadLedger(launchSkippedID: ledger.launchSkippedID)
        try expect(relaunched.skipsLaunchDownload(of: "parakeet-tdt-v3"), "kept across a launch")

        var asked = relaunched
        asked.began("parakeet-tdt-v3", isDownload: true)
        try expect(!asked.skipsLaunchDownload(of: "parakeet-tdt-v3"), "a Download or a dictation that needs it ends the hold")

        var picked = relaunched
        picked.dictationModelChanged(to: "parakeet-tdt-v3")
        try expect(picked.skipsLaunchDownload(of: "parakeet-tdt-v3"), "picking the same model again keeps it")
        picked.dictationModelChanged(to: "whisper-small")
        try expect(picked.launchSkippedID == nil, "another dictation model ends it")

        var other = relaunched
        other.began("whisper-small", isDownload: true)
        try expect(other.skipsLaunchDownload(of: "parakeet-tdt-v3"), "another model's download leaves it")
    }

    /// Review: cancel, then Download again within a second, and the dictation
    /// that waited on the first download read the new one's cleared flag.
    private static func aCancelThenDownloadStillCountsTheCancel() throws {
        var ledger = ModelDownloadLedger()
        ledger.began("whisper-large-v3", isDownload: true)
        let before = ledger.cancelCount("whisper-large-v3")
        ledger.cancel("whisper-large-v3")
        ledger.began("whisper-large-v3", isDownload: true)
        try expect(!ledger.wasCancelled("whisper-large-v3"), "the new download clears the flag")
        try expect(ledger.cancelCount("whisper-large-v3") == before + 1, "but the count still shows the cancel")
        ledger.cancel("whisper-large-v3")
        ledger.cancel("whisper-large-v3")
        try expect(ledger.cancelCount("whisper-large-v3") == before + 2, "a refused cancel isn't counted")
        try expect(ledger.cancelCount("whisper-small") == 0, "other models count their own")
    }

    private static func onlyADownloadCanBeCancelled() throws {
        var ledger = ModelDownloadLedger()
        ledger.began("whisper-small", isDownload: false)
        try expect(!ledger.canCancel("whisper-small"), "a model loading from disk has no download to cancel")
        try expect(!ledger.cancel("whisper-small"), "cancelling a load is refused")
        try expect(!ledger.wasCancelled("whisper-small"), "a refused cancel isn't remembered")
        try expect(!ledger.isDraining("whisper-small"), "a refused cancel leaves nothing to remove")

        ledger.began("whisper-small", isDownload: true)
        try expect(ledger.canCancel("whisper-small"), "a download can be cancelled")
        try expect(ledger.cancel("whisper-small"), "the cancel applies")
        try expect(!ledger.cancel("whisper-small"), "a second cancel of the same download is a no-op")
        try expect(!ledger.canCancel("whisper-small"), "a cancelled download offers no second cancel")
    }

    private static func aCancelIsRememberedUntilTheNextStart() throws {
        var ledger = ModelDownloadLedger()
        ledger.began("parakeet-tdt-v3", isDownload: true)
        ledger.cancel("parakeet-tdt-v3")
        try expect(ledger.wasCancelled("parakeet-tdt-v3"), "a dictation waiting on the download can tell it was cancelled")
        try expect(ledger.drainingIDs == ["parakeet-tdt-v3"], "its files are queued for removal")

        ledger.began("parakeet-tdt-v3", isDownload: true)
        try expect(!ledger.wasCancelled("parakeet-tdt-v3"), "a new download forgets the old cancel")
        try expect(ledger.canCancel("parakeet-tdt-v3"), "and can be cancelled in turn")
        try expect(ledger.isDraining("parakeet-tdt-v3"), "the old one still drains until it returns")
    }

    private static func twoDownloadsCancelIndependently() throws {
        var ledger = ModelDownloadLedger()
        ledger.began("whisper-small", isDownload: true)
        ledger.began("whisper-large-v3", isDownload: true)
        ledger.cancel("whisper-small")
        try expect(ledger.canCancel("whisper-large-v3"), "cancelling one download leaves the other running")
        try expect(!ledger.wasCancelled("whisper-large-v3"), "the other isn't marked cancelled")
        ledger.cancel("whisper-large-v3")
        try expect(ledger.drainingIDs == ["whisper-large-v3", "whisper-small"], "both drain, sorted for storage")
        ledger.drained("whisper-small")
        try expect(ledger.drainingIDs == ["whisper-large-v3"], "each drains on its own")
    }

    private static func drainsAreCountedPerCancel() throws {
        var ledger = ModelDownloadLedger()
        ledger.began("whisper-tiny", isDownload: true)
        ledger.cancel("whisper-tiny")
        ledger.began("whisper-tiny", isDownload: true)
        ledger.cancel("whisper-tiny")
        ledger.drained("whisper-tiny")
        try expect(ledger.isDraining("whisper-tiny"), "the second cancelled preparation is still out")
        ledger.drained("whisper-tiny")
        try expect(!ledger.isDraining("whisper-tiny"), "drained once both returned")
        ledger.drained("whisper-tiny")
        try expect(ledger.drainingIDs.isEmpty, "an extra drain never goes negative")
    }

    private static func aFinishedDownloadCannotBeCancelled() throws {
        var ledger = ModelDownloadLedger()
        ledger.began("whisper-base", isDownload: true)
        ledger.ended("whisper-base")
        try expect(!ledger.canCancel("whisper-base"), "an installed or failed model has nothing to cancel")
        try expect(!ledger.cancel("whisper-base"), "and a late cancel is refused")
        try expect(!ledger.wasCancelled("whisper-base"), "so a failure stays a failure")
    }
}
