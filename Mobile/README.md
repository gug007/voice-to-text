# Voice to Text for iPhone

A companion to the Mac app: record with the microphone, transcribe on the device with Parakeet TDT v3, then get a Summary and Action Items with your own OpenAI key.

The engine, the chunked transcriber, the History index format and the insight prompts are the Mac app's own files, compiled into this target from `../VoiceToText/VoiceToText` (the list is in `project.yml`). A change to one of them changes both apps.

## Build

```
brew install xcodegen go
./scripts/build-tailscale.sh
cd Mobile
xcodegen generate
open VoiceToTextMobile.xcodeproj
```

Run `xcodegen generate` again after adding or removing a source file. A device build needs a development team set in Xcode.

Debug builds accept launch arguments for driving the app without touching it: `-debugDownloadModel YES`, `-debugImport <path>`, `-debugOpenFirst YES`, `-debugTab Summary`, `-debugRecord YES`, `-debugStopAfter <seconds>`.

## Mac

The Mac section in Settings signs this iPhone in to Tailscale inside the app (no Tailscale app needed) and finds every Mac running VoiceToText with Control from iPhone on (Mac app → Conversations), signed in to the same account. The phone talks to all of them at once, each polled on its own, so a slow or sleeping Mac never holds up another. The main screen shows one card per Mac that is connected or that Tailscale reports online, each with its own Record on Mac, Stop or Retry; the library lists "Conversations on <Mac>" for each connected Mac, to read and play back. Settings lists every Mac on the account with its connection, offline ones included. The wire format is `../VoiceToText/VoiceToText/Remote/RemoteProtocol.swift`, shared with the Mac.

Tailscale comes from `../scripts/build-tailscale.sh`, which builds libtailscale (Go) for the device, the simulator and the Mac into a local Swift package at `../VoiceToText/Vendor/TailscaleKit` (gitignored). Run it once before `xcodegen generate` on a fresh clone; it needs Go (`brew install go`) and skips itself when the package is current.

To try it without a Tailscale account, run the Mac's Debug build with `-debugRemoteLoopback YES` (it serves the same API on 127.0.0.1) and launch this app in the simulator with `-debugRemoteLoopback YES` too. Add `-debugRemoteLoopbackPorts 47610,47611` to make loopback show one Mac per port (anything that speaks the protocol on those ports will do), for trying several Macs at once. More launch arguments for that: `-debugRemote start|stop|cycle` (with `-debugRemoteHold <seconds>` between the two halves of `cycle`), `-debugRemoteOpen list|first|<conversation id>`, `-debugRemoteMac <name>` (the Mac those two act on, by the name its card shows; the first Mac without it), `-debugRemotePlay YES` (download and play the opened conversation), `-debugShowSettings YES`, `-debugRemoteSignIn YES` (start the real Tailscale sign-in). The Mac's Debug build also takes `-debugRemoteStopCancels YES` (Stop discards the take, so a test leaves History alone) and `-debugRemoteNoBrowser YES` (log the sign-in URL instead of opening it).
