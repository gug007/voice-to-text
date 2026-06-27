# Triggering VoiceToText from another app

VoiceToText registers the custom URL scheme **`voicetotext://`**. Any other app can
open one of these URLs to start/stop dictation. When dictation finishes, the
transcript is pasted (synthetic ⌘V) into whatever app is **frontmost** — so if you
open the URL *without activating VoiceToText*, the text lands in your app.

This means you don't embed any recording or transcription code in your app. You add
one button that opens a URL; the installed VoiceToText app does the rest.

## Commands

| URL                     | Effect                                                        |
| ----------------------- | ------------------------------------------------------------ |
| `voicetotext://toggle`  | Start recording if idle; stop & transcribe if recording. **Use this for a single button.** |
| `voicetotext://start`   | Start recording (no-op if already recording).                |
| `voicetotext://stop`    | Stop & transcribe (no-op if not recording).                  |
| `voicetotext://cancel`  | Cancel the current recording without transcribing.           |

An unknown or missing command (e.g. `voicetotext://`) is treated as `toggle`.

## The one rule: don't activate VoiceToText

The transcript is typed into the **frontmost** app. If opening the URL brings
VoiceToText to the front, your app loses focus and the text goes to the wrong place.
So always open the URL with activation **disabled** — then your app stays frontmost
and receives the dictated text.

## SwiftUI button (recommended)

```swift
import SwiftUI
import AppKit

struct DictateButton: View {
    var body: some View {
        Button {
            triggerDictation()
        } label: {
            Label("Dictate", systemImage: "mic.fill")
        }
    }

    private func triggerDictation() {
        guard let url = URL(string: "voicetotext://toggle") else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false          // keep *this* app frontmost
        NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
    }
}
```

## AppKit button

```swift
let button = NSButton(title: "🎤 Dictate", target: self, action: #selector(dictate))

@objc func dictate() {
    guard let url = URL(string: "voicetotext://toggle") else { return }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    NSWorkspace.shared.open(url, configuration: config)
}
```

## Test it from the terminal

The `-g` flag opens the URL in the background (does not bring VoiceToText forward),
which mirrors `activates = false`:

```sh
open -g voicetotext://toggle    # start; run again to stop & transcribe
open -g voicetotext://start
open -g voicetotext://stop
open -g voicetotext://cancel
```

## Requirements / notes

- **VoiceToText must be installed** (in `/Applications`) so LaunchServices can resolve
  the scheme. If it isn't running, opening the URL launches it (in the background) and
  the first toggle may take a moment while the model loads; subsequent toggles are instant.
- VoiceToText needs **Microphone** and **Accessibility** permissions (it prompts on first use).
- "Review before paste" is on by default: after recording, a small panel appears to
  confirm/edit before the text is pasted. Press the hotkey (or send `toggle` again) to
  confirm. You can disable this in VoiceToText → Settings.
- If you ship your own build of VoiceToText with a different bundle id (e.g. the
  `*.dev` build from `scripts/dev.sh`), it registers the same `voicetotext://` scheme;
  whichever copy LaunchServices has indexed most recently will handle the URL.
