#if arch(x86_64)
import Foundation

extension ModelDescriptor {
    /// This catalog entry as the Intel slice offers it: a WhisperKit model
    /// takes its whisper.cpp build's download size, and its Intel note where
    /// there is one. Everything else — id, name, order, languages, benchmarks —
    /// stays as it is.
    nonisolated var adaptedForIntel: ModelDescriptor {
        guard backend == .whisperKit, let model = WhisperCppModel.model(forCatalogID: id) else { return self }
        return ModelDescriptor(
            id: id,
            displayName: displayName,
            backend: backend,
            backendModelId: backendModelId,
            approxSizeMB: model.approxSizeMB,
            languages: languages,
            languageCodes: languageCodes,
            autoPickable: autoPickable,
            notes: model.intelNotes ?? notes,
            speed: speed,
            pricePerHourUSD: pricePerHourUSD,
            benchmarks: benchmarks
        )
    }
}
#endif
