# VoiceToText — Free Offline Dictation App for macOS

**Free speech-to-text for Mac, with source available on GitHub.** Press a global shortcut, speak, and paste the transcript into any app — Claude Code, Codex, Cursor, Slack, Notes, VS Code, Chrome, and more. Local transcription is the default: the Parakeet model runs on your Mac and works offline once it has been downloaded. OpenAI and ElevenLabs models are optional: they're used only when you select one and add your own API key.

A free alternative to Wispr Flow, Superwhisper, MacWhisper, and Apple Dictation.

**Website:** [voicetotext.cc](https://voicetotext.cc)

![VoiceToText demo](assets/demo.gif)

## Features

- **Free, source available** — no paid tier, no VoiceToText account, and no analytics or telemetry in the app; the source is on GitHub
- **Local by default** — the default model, Parakeet TDT v3, downloads once on first launch and then runs on your Mac; five local Whisper models are available too
- **Offline after setup** — with Parakeet, the default, dictation and transcription need no network once the model is downloaded (Whisper models need a connection each time they load)
- **Global shortcut** — `⌥ Space` toggles dictation by default; switch to hold-to-record, or bind any key with a modifier, a lone F1–F20, or Right Control
- **Review before pasting** — edit the transcript, record another take at the cursor, or run an AI action before anything reaches the other app (on by default; turn it off for instant paste)
- **Pastes into any app** — the text goes in with ⌘V and your previous clipboard is restored afterwards, so it works anywhere you can paste text
- **Conversations** — record your microphone and the other people on a call (system audio) together, or drop in an audio or video file; transcribed when you stop
- **Speaker labels** — optional, through OpenAI's GPT-4o Transcribe Diarize; rename "Speaker 1" to real names
- **AI insights** — Summary, Action Items, and your own prompts on any recording, with your OpenAI key
- **Searchable History** — every dictation and conversation is kept on your Mac with its audio; search, favorite, replay, copy, and re-transcribe with another model
- **15 speech models** — 6 local and 9 cloud (OpenAI and ElevenLabs), including four live models
- **Built for AI agents** — speak prompts into Claude Code, Codex, Cursor, Copilot Chat, ChatGPT, and other LLM tools
- **Scriptable** — a `voicetotext://` URL scheme for Raycast, Shortcuts, Stream Deck, and scripts
- **Native** — a SwiftUI/AppKit Mac app, not Electron

## Download

[**Download VoiceToText**](https://github.com/gug007/voice-to-text/releases/latest/download/VoiceToText.dmg)

The app is signed and notarized. Every release is on [GitHub Releases](https://github.com/gug007/voice-to-text/releases).

## Install

1. Open the DMG and drag **VoiceToText** to `/Applications`.
2. Launch it. The default Parakeet model starts downloading in the background.
3. Grant Microphone and Accessibility permissions when prompted.
4. Put the cursor in any text field and press `⌥ Space`, speak, then press `⌥ Space` again.
5. The transcript opens in a review panel. Press `Return` (or `⌥ Space` once more) to paste it into the app you were in.

If you'd rather skip the review step, turn off **Review before pasting** in Settings → General and the text is pasted as soon as you stop.

## Requirements

- macOS 15.0 or later
- Apple Silicon (M1 or newer); Intel Macs are not supported by current builds
- An internet connection for the first model download, update checks, loading a Whisper model, and any cloud models or AI features you choose to use

## How it works

### Dictation

- **Toggle or hold.** Press the shortcut to start and again to stop, or switch to **Hold to record** in Settings → Shortcut.
- **Recording card.** A small floating card shows a live level meter, the elapsed time, and Cancel / Finish buttons. `Esc` cancels (you can turn that off).
- **Review panel.** `Return` pastes, `Shift+Return` adds a new line, `Esc` discards the take, and `⌘R` records another take and inserts it at the cursor, so a long prompt can be spoken in passes.
- **Paste, not typing.** VoiceToText saves your clipboard, puts the text on it, sends `⌘V` to the frontmost app, and restores the previous clipboard about a quarter of a second later. Fields that block pasting won't receive text.
- **No voice commands.** Saying "new line" or "comma" writes those words. There's no built-in filler-word removal; an AI action can clean that up if you want.
- **Resilient capture.** If the microphone changes mid-take (AirPods switching profiles, for example), recording restarts automatically. If it can't, the audio captured so far is still transcribed. A failed transcription keeps the audio so you can retry.
- The app uses the macOS default input device; there's no microphone picker.

### AI actions

Six built-in actions in the review panel: **Clean transcript, To English, Improve prompt, Fix grammar, Summarize, Essentials only**. You can add your own (a name plus an instruction).

- All actions are **off by default**. Turn them on in Settings → Actions and add an OpenAI API key.
- Run one with a click or `⌘1`–`⌘9`; chain several and step back with Undo.
- They never run automatically. Each run sends the transcript text to OpenAI (`gpt-5.5`) on your key.

### Conversations

Conversations is VoiceToText's meeting recorder.

- **Mic + system audio.** Records your microphone and whatever your Mac plays, so it captures the other people on Zoom, Google Meet, Teams, FaceTime, Webex, Discord, or any other app. No bot joins the call.
- **Start it three ways:** Start Recording in the Conversations pane, the menu bar item, or an optional **Conversation shortcut** (no default key; press to start, press again to stop and transcribe).
- **Transcribed when you stop,** not live. Long recordings are split at quiet points and transcribed in parts. There's no pause.
- **Its own model.** Conversations and uploads have a separate Transcription model setting (default: same as dictation). Live models aren't offered here.
- **Upload a file.** Choose **Upload File…** or drag one audio or video file onto the pane — anything macOS can read, such as MP3, M4A, WAV, AIFF, FLAC, MP4, or MOV. With the default local model it's transcribed on your Mac. History keeps the extracted audio, not the original video.
- **Speaker labels.** Only with the cloud model GPT-4o Transcribe Diarize (OpenAI key, $0.36/hr). Turns are labeled Speaker 1, Speaker 2…; use **Name speakers** to rename them, and the names carry into copies, AI insights, and search. Local models produce one unlabeled transcript.
- **Crash-safe.** Audio is written to disk as it records. If the app quits unexpectedly, the recording appears in History on the next launch; use Regenerate to transcribe it.
- Needs **Screen Recording** permission, because that's how macOS provides system audio. VoiceToText records audio only, never the screen.

### History

- Every dictation and every conversation or upload is saved on your Mac with its audio and transcript, in `~/Library/Application Support/VoiceToText/History`.
- Dictations are saved by default. Turn off **Save recordings** in History to stop saving them; takes you cancel in review are removed. Conversations and uploads are always saved.
- **Search transcripts** finds text across transcripts, earlier versions, summaries, action items, custom results, speaker names, model, and date.
- Favorite, play, copy, or delete with a 5-second Undo (`⌘Z`). **Clear All** is undoable too.
- **Regenerate** any recording with any of the 15 models and keep each version side by side.
- History keeps the newest 200 recordings, dictations and conversations combined; favorites count toward the limit.
- There's no export, sharing, sync, or transcript editing — copy to the clipboard to take text elsewhere.

### AI insights

Open the sparkles menu on any recording (conversation rows also show Summary / Action items / Custom chips):

- **Summary** — a short summary of the transcript.
- **Action Items** — a checklist of tasks, with an owner and due date only when someone actually said one. Tick items off, or copy them as a Markdown checklist.
- **Custom prompt** — "Format with AI" with your own instruction, such as "Rewrite this as meeting minutes". Up to three custom results per recording.

Insights use your OpenAI key and `gpt-5.5`, and send the transcript text (with speaker names) to OpenAI. Results are saved with the recording and are searchable. If you regenerate the transcript, existing insights are kept and marked as out of date.

## Models

15 models: 6 that run on your Mac and 9 in the cloud. Pick one in Settings → Models, which shows a 1–10 quality score (derived from published third-party word error rates; not VoiceToText's own tests) and the provider's price per hour.

**On your Mac** — free, downloaded once from Hugging Face. Audio never leaves the Mac.

Parakeet, the default, works with the network off after its one-time download. Whisper models also transcribe on your Mac, and your audio never leaves it, but the current version contacts Hugging Face whenever it loads a Whisper model (after each launch), so loading one needs an internet connection. For a fully offline Mac, use Parakeet.

| Model | Notes |
| --- | --- |
| Parakeet TDT v3 | Default and recommended. 25 European languages. |
| Whisper Large v3 Turbo | English. |
| Whisper Large v3 | English. Highest quality score among local models. |
| Whisper Small | English. Smaller download, more mistakes. |
| Whisper Base | English. |
| Whisper Tiny | English. For testing your setup. |

Models take from under 100 MB to about 1.6 GB on disk, depending on which one you pick.

**Cloud** — bring your own API key. Audio goes directly from your Mac to the provider, which bills you.

| Model | Provider | Price | Notes |
| --- | --- | --- | --- |
| Scribe v2 Realtime | ElevenLabs | $0.39/hr | LIVE — text appears word by word as you speak. 90+ languages. |
| GPT Live Transcribe | OpenAI | $1.02/hr | LIVE — text appears phrase by phrase, after each short pause. |
| GPT Realtime Whisper | OpenAI | $1.02/hr | LIVE — text appears only when you stop. |
| GPT-4o Transcribe Realtime | OpenAI | $0.36/hr | LIVE — text appears phrase by phrase, after each short pause. |
| GPT Transcribe | OpenAI | $0.27/hr | Highest quality score in the catalog. |
| GPT-4o Transcribe | OpenAI | $0.36/hr | |
| GPT-4o Transcribe Diarize | OpenAI | $0.36/hr | Labels speakers (Conversations and uploads). |
| GPT-4o Mini Transcribe | OpenAI | $0.18/hr | Lowest price. |
| Whisper-1 | OpenAI | $0.36/hr | |

LIVE models are for dictation only. Prices are the providers' list prices as of September 2026.

### Languages

There's no language picker; each model decides.

- **Parakeet TDT v3** (default): 25 European languages, detected automatically.
- **Local Whisper models:** English only in VoiceToText today.
- **Cloud models:** OpenAI models cover 99+ languages and ElevenLabs Scribe 90+, detected automatically.

For a language outside Parakeet's 25, choose a cloud model.

## Mac integration

- **Window and menu bar.** VoiceToText is a regular Mac app with a window and a Dock icon, plus a menu bar item for starting and stopping dictation or a conversation. To run it from the menu bar only, turn off **Show in Dock**.
- **Runs in the background.** Closing the window keeps the app running. Launch at login is turned on at first run.
- **Appearance:** System, Light, or Dark.
- **URL scheme.** `voicetotext://toggle`, `start`, `stop`, and `cancel` control dictation from other apps and scripts, for example `open -g voicetotext://toggle`. See [INTEGRATION.md](INTEGRATION.md).
- **Updates.** The app checks GitHub Releases at launch and once a day. Nothing installs without you: choose Install Update, Later, or Skip This Version. The Updates pane has Check Now and release notes.

## Permissions

| Permission | Why |
| --- | --- |
| Microphone | Recording dictation and your side of a conversation. |
| Accessibility | Pasting into other apps. Recording won't start without it. |
| Input Monitoring | Only if you use Right Control on its own as the shortcut. |
| Screen Recording | Only for Conversations, to capture system audio. The screen is never recorded. |

## Privacy and network

- **With local models and no API keys,** the app connects to the internet only to reach Hugging Face (model downloads, plus a check each time a Whisper model loads) and to check GitHub Releases for updates. Your audio and transcripts stay on the Mac.
- **Cloud transcription models** send your audio directly to OpenAI or ElevenLabs under your API key. Provider charges apply.
- **AI actions and AI insights** send transcript text to OpenAI under your key when you run them.
- **Adding an API key** sends one request to that provider to check the key. Keys are stored in the app's preferences on this Mac.
- **No VoiceToText servers,** no account, and no analytics or telemetry in the app. (The website, voicetotext.cc, uses Google Analytics.)
- **History is saved locally,** including dictation audio by default — see [History](#history).

## Keywords

Free macOS dictation, offline speech-to-text Mac, voice-to-text Mac, Whisper Mac app, Parakeet Mac, local speech recognition, push-to-talk dictation, meeting transcription Mac, system audio recorder, voice prompting for Claude Code, Codex CLI voice input, Cursor voice dictation, talk to AI coding agents, source-available Wispr Flow alternative, Superwhisper alternative, MacWhisper alternative.
