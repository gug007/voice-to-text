# Integrating VoiceToText into another app

There are two ways in:

- **[App API](#app-api)** — your app draws its own recorder and gets the
  transcript back as text. VoiceToText records and transcribes with the user's
  chosen model, but shows nothing and pastes nothing. Use this when you want
  dictation to look like part of your app.
- **[URL scheme](#url-scheme)** — one button that opens `voicetotext://toggle`.
  VoiceToText shows its own recording card and pastes the transcript into the
  frontmost app. No code beyond opening a URL.

# App API

A local socket that speaks newline-delimited JSON. Your app sends `start` and
`stop`; VoiceToText streams back what your recorder needs to show — model
loading progress, the microphone level, live words for live models — and then
the transcript.

## Connecting

| Build | Socket |
| --- | --- |
| VoiceToText (release) | `~/Library/Application Support/VoiceToText/api.sock` |
| Any other build (e.g. `scripts/dev.sh`) | `~/Library/Application Support/VoiceToText/api-dev.sock` |

- The socket exists while VoiceToText runs with **Settings → General → Allow other
  apps to dictate** on (the default). It is `0600`, and VoiceToText only accepts
  connections from processes running as the same user.
- A copy that supports the API has `VoiceToTextAPIVersion` (currently `1`) in its
  `Info.plist`, so you can check an installed copy without launching it.
- If it isn't running, launch it without its window and without stealing focus,
  then poll for the socket (a cold start with a local model takes a few seconds):

  ```sh
  open -g -a VoiceToText --args --background
  ```

## Messages

One JSON object per line, UTF-8, in both directions.

Requests carry an `id` (number or string), echoed by the response:

```json
{"id": 1, "method": "start", "params": {"client": "my-app"}}
{"id": 1, "ok": true, "result": {"model": {"id": "parakeet-tdt-v3", "name": "Parakeet TDT v3", "live": false, "local": true}}}
{"id": 2, "ok": false, "error": {"code": "busy", "message": "VoiceToText is already recording."}}
```

Events have an `event` name and no `id`. They go only to the connection that
started the recording.

## Methods

| Method | What it does | Response |
| --- | --- | --- |
| `status` | Current state, model, and microphone permission. | `{"api", "app", "version", "state", "busy", "owner", "microphone", "model", "elapsed"?}` |
| `start` | Prepares the model (downloading it on first use) and starts recording. | Sent once recording has started, with the `model`, or an error. |
| `stop` | Stops recording and transcribes. | Sent at once; the text arrives as a `transcript` event. |
| `cancel` | Drops the recording or transcription in progress. Safe to send any time. | `{}` |

- `status.state` is `idle`, `preparing`, `recording`, or `transcribing`. `busy` is
  true while the hotkey dictation or a conversation holds the microphone, when
  `start` would be refused. `microphone` is `granted`, `denied`, or
  `undetermined` (the first `start` asks).
- One recording at a time, owned by the connection that started it. Closing that
  connection cancels it. While it runs, VoiceToText's own shortcut does nothing.

## Events

| Event | Fields | Meaning |
| --- | --- | --- |
| `state` | `state`, `model`?, `progress`?, `message`?, `interrupted`? | The session moved: `preparing` (repeats as `progress` 0–1 and `message` change while a model downloads or loads; `progress` is omitted while unknown), `recording`, `transcribing` (`interrupted: true` when the microphone went away and what was captured is being transcribed), `idle`. |
| `level` | `level` | Microphone level, 0–1, about 10–15 times a second while recording. |
| `partial` | `text` | Live models only: the words so far, replacing the previous `partial`. |
| `transcript` | `text`, `duration`, `model` | The final, cleaned-up transcript. |
| `error` | `code`, `message`, `savedToHistory`? | The take ended without a transcript. |

Every session ends with `state: idle` — after `transcript`, after `error`, or
after a `cancel`.

Successful transcripts are saved to History like any dictation (if Save
recordings is on). A take whose transcription fails is kept in History with its
audio (`savedToHistory: true`), so the user can transcribe it again there.

## Error codes

| Code | When |
| --- | --- |
| `busy` | Something else is recording: the hotkey, a conversation, or another app. |
| `microphone_denied` | VoiceToText has no microphone access. |
| `no_model`, `model_unavailable` | No model is selected, or it couldn't be downloaded or loaded. |
| `api_key_missing` | The selected cloud model has no API key. |
| `recorder_failed` | The audio device didn't start. |
| `not_recording` | `stop` with nothing recording. |
| `too_short`, `no_speech` | Nothing worth transcribing was said. |
| `transcription_failed` | The model or the provider failed (network, key, quota…). |
| `cancelled` | The `start` was cancelled before recording began. |
| `invalid_request`, `unknown_method` | The request couldn't be read. |

`message` is always a sentence you can show the user as is.

## Try it

Records five seconds and prints the transcript:

```sh
python3 - <<'PY'
import json, os, socket, time
s = socket.socket(socket.AF_UNIX)
s.connect(os.path.expanduser("~/Library/Application Support/VoiceToText/api.sock"))
f = s.makefile("rwb")
f.write(b'{"id":1,"method":"start","params":{"client":"shell"}}\n'); f.flush()
while (reply := json.loads(f.readline())).get("id") != 1:
    pass  # preparing / level events until recording starts
if not reply["ok"]:
    raise SystemExit(reply["error"]["message"])
print("Speak now…"); time.sleep(5)
f.write(b'{"id":2,"method":"stop"}\n'); f.flush()
for line in f:
    msg = json.loads(line)
    if msg.get("event") == "transcript": print(msg["text"])
    if msg.get("event") == "error": print(msg["message"])
    if msg.get("event") == "state" and msg["state"] == "idle": break
PY
```

# URL scheme

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
