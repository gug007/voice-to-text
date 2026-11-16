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

The Mac section in Settings signs this iPhone in to Tailscale inside the app (no Tailscale app needed) and finds every Mac running VoiceToText with Control from iPhone on (Mac app → Conversations), signed in to the same account. The phone talks to all of them at once, each polled on its own, so a slow or sleeping Mac never holds up another. The main screen opens with one card per Mac that is connected or that Tailscale reports online: its short name ("MacBook Pro" for "Gurgen’s MacBook Pro (2)", the full name when two Macs would share one), its state, Stop and live listen while it records, Retry when it can't be reached, and its two newest conversations with See all. Under the list, a switch picks where the one Record button records, This iPhone or a Mac (segmented for up to two Macs, a menu beyond); on a Mac the button turns into Stop with the timer while that Mac records. The choice is remembered. Settings lists every Mac on the account with its connection, offline ones included. The wire format is `../VoiceToText/VoiceToText/Remote/RemoteProtocol.swift`, shared with the Mac.

While a Mac records with listening allowed on it (`liveListen` in its status), the headphones button beside Stop plays the Mac's mixed audio live on this iPhone: AAC-LC, 16 kHz mono, one raw packet per frame in the framing of `../VoiceToText/VoiceToText/Remote/LiveAudioWire.swift`, decoded without a magic cookie (`Model/LiveAudioDecoder.swift`) and played from `Model/LiveListener.swift`. Playback starts once about 0.4 s is buffered, rebuffers on an underrun, and drops back to live when more than 2 s is waiting. A dropped stream is retried three times (0.5, 1 and 2 s apart) while the Mac still reports recording, then the card says why it stopped. The request carries `?client=<id>`, a UUID made once per install, so the Mac replaces this phone's own dead stream when it reconnects instead of counting it against the limit. A stream that ends because the Mac stopped just stops; 403, 409 and 503 show the Mac's own sentence. One Mac at a time: listening to another stops the first, and recording on this iPhone stops it too. It keeps playing in the background and on the lock screen, where the Now Playing controls stop it, and the phone keeps Tailscale up and keeps polling that Mac until it ends. A call or Siri stops it for good.

Tailscale comes from `../scripts/build-tailscale.sh`, which builds libtailscale (Go) for the device, the simulator and the Mac into a local Swift package at `../VoiceToText/Vendor/TailscaleKit` (gitignored). Run it once before `xcodegen generate` on a fresh clone; it needs Go (`brew install go`) and skips itself when the package is current.

To try it without a Tailscale account, run the Mac's Debug build with `-debugRemoteLoopback YES` (it serves the same API on 127.0.0.1) and launch this app in the simulator with `-debugRemoteLoopback YES` too. Add `-debugRemoteLoopbackPorts 47610,47611` to make loopback show one Mac per port (anything that speaks the protocol on those ports will do), for trying several Macs at once. More launch arguments for that: `-debugRemote start|stop|cycle` (with `-debugRemoteHold <seconds>` between the two halves of `cycle`), `-debugRemoteOpen list|first|<conversation id>`, `-debugRemoteMac <name>` (the Mac those two act on, by its full name, as Settings shows it; the first Mac without it), `-debugRemotePlay YES` (download and play the opened conversation), `-debugRemoteListen YES` (start listening live as soon as that Mac reports recording with listening allowed), `-debugRemoteListenMuted YES` (decode and play live audio at zero volume, so a simulator on the recording Mac doesn't feed its own speakers back into the recording), `-debugShowSettings YES`, `-debugRemoteSignIn YES` (start the real Tailscale sign-in). The Mac's Debug build also takes `-debugRemoteStopCancels YES` (Stop discards the take, so a test leaves History alone) and `-debugRemoteNoBrowser YES` (log the sign-in URL instead of opening it).
