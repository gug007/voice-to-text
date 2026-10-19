import Foundation
import SwiftUI

/// The executable's entry point. On Apple Silicon it only starts the app.
///
/// In the Intel slice the same executable is also the transcription worker:
/// `TranscribeSupervisor` starts it again with `--transcribe-worker`, and that
/// process runs transcribe.cpp (`TranscribeWorker`) and exits without ever
/// touching AppKit or SwiftUI. Checked first, before anything of the app's
/// own is created.
@main
enum AppEntry {
    static func main() {
        #if arch(x86_64)
        TranscribeWorkerEntry.runIfRequested(arguments: CommandLine.arguments)
        #endif
        VoiceToTextApp.main()
    }
}
