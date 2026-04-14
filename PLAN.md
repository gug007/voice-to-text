# VoiceToText — Implementation Plan

A native macOS dictation app: hold a global hotkey, speak, release, and the transcribed text is typed into whatever app is focused. Local-first (Parakeet / Whisper on the Apple Neural Engine), with a future cloud option.

---

## Goals

- **Local-first.** Works offline. No data leaves the device by default.
- **Multi-model.** User can download and switch between several STT models.
- **Low-latency.** Target <500ms from key release to first character typed.
- **Native feel.** Menu-bar app, no dock icon, no main window. Settings via standard macOS UI.
- **Universal input.** Types into any focused app (browser, Slack, editor, terminal).

## Non-goals (v1)

- Live streaming transcription as you speak (we use record-then-transcribe on key release).
- Real-time translation.
- Multi-device sync, accounts, cloud history.
- Windows / Linux support.

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│                  VoiceToText.app                 │
│                                                  │
│  ┌────────────┐    ┌──────────────────────────┐  │
│  │ Menu Bar   │    │      Settings Window     │  │
│  │ (StatusBar)│    │  (model picker, hotkey)  │  │
│  └─────┬──────┘    └──────────────┬───────────┘  │
│        │                          │              │
│  ┌─────▼──────────────────────────▼───────────┐  │
│  │            DictationController             │  │
│  │  (orchestrates record → transcribe → type) │  │
│  └─┬────────────┬────────────────┬────────────┘  │
│    │            │                │                │
│ ┌──▼───┐  ┌─────▼─────┐    ┌─────▼──────┐         │
│ │Hotkey│  │AudioRecord│    │KeystrokeOut│         │
│ │Carbon│  │AVAudioEng │    │  CGEvent   │         │
│ └──────┘  └─────┬─────┘    └────────────┘         │
│                 │                                  │
│        ┌────────▼─────────┐                        │
│        │TranscriptionEngine│  (protocol)           │
│        └────────┬─────────┘                        │
│           ┌─────┴──────┐                           │
│      ┌────▼───┐  ┌─────▼──────┐                    │
│      │Whisper │  │ FluidAudio │                    │
│      │  Kit   │  │ (Parakeet) │                    │
│      └────────┘  └────────────┘                    │
│           │            │                           │
│      ┌────▼────────────▼────┐                      │
│      │    ModelRegistry     │                      │
│      │  (catalog + state)   │                      │
│      └──────────┬───────────┘                      │
│                 │                                  │
│        ┌────────▼─────────┐                        │
│        │  ModelDownloader │                        │
│        │ (progress, disk) │                        │
│        └──────────────────┘                        │
└──────────────────────────────────────────────────┘
```

### Module responsibilities

| Module | Responsibility |
|---|---|
| `VoiceToTextApp` | App entry, NSApplicationDelegate, lifecycle |
| `MenuBarController` | NSStatusItem, recording indicator, quick switches |
| `SettingsView` | SwiftUI settings (Models, Hotkey, General tabs) |
| `OnboardingView` | First-launch permissions + starter model picker |
| `DictationController` | Glue: hotkey down → record → key up → transcribe → type |
| `HotkeyManager` | Global hotkey registration (Carbon RegisterEventHotKey) |
| `AudioRecorder` | AVAudioEngine tap, downsample to 16kHz mono Float32 |
| `KeystrokeOutput` | CGEventKeyboardSetUnicodeString into focused app |
| `TranscriptionEngine` (protocol) | `transcribe(samples: [Float]) async throws -> String` |
| `WhisperKitEngine` | WhisperKit implementation |
| `FluidAudioEngine` | FluidAudio (Parakeet) implementation |
| `ModelRegistry` | Catalog + active model, persists to UserDefaults |
| `ModelDownloader` | Wraps each SDK's download API, exposes progress |
| `PermissionsService` | Check/request mic + accessibility permissions |

---

## Models supported (v1)

User can download any subset on demand. Models stored in `~/Library/Application Support/VoiceToText/Models/`.

| ID | Engine | Size | Languages | Notes |
|---|---|---|---|---|
| `parakeet-tdt-v3` ⭐ | FluidAudio | ~600 MB | 25 EU + JA | Default — fastest, lowest latency |
| `whisper-large-v3-turbo` ⭐ | WhisperKit | ~1.5 GB | 99 | Recommended for multilingual |
| `whisper-large-v3` | WhisperKit | ~3.1 GB | 99 | Highest accuracy |
| `whisper-medium` | WhisperKit | ~1.5 GB | 99 | Older, lower than turbo |
| `whisper-small` | WhisperKit | ~466 MB | 99 | Lightweight option |
| `whisper-base` | WhisperKit | ~142 MB | 99 | Very small |
| `whisper-tiny` | WhisperKit | ~75 MB | 99 | Tiniest, lowest accuracy |

⭐ = recommended in onboarding.

---

## Permissions required

| Permission | Why | When prompted |
|---|---|---|
| **Microphone** (NSMicrophoneUsageDescription) | Record audio to transcribe | First record |
| **Accessibility** | Inject keystrokes into other apps | Onboarding (deep-link to System Settings) |
| **Network** (only if cloud added later) | Send audio to API | When enabling cloud backend |

App is **non-sandboxed** (sandbox makes accessibility + global hotkeys awkward). Hardened runtime stays on for notarization later.

---

## UX flows

### First launch
1. Welcome screen explains what the app does.
2. "Grant Microphone" → triggers system prompt.
3. "Grant Accessibility" → opens System Settings → Privacy → Accessibility (deep link).
4. "Pick a model": three cards — Parakeet (Fast), Whisper Turbo (Multilingual), Whisper Small (Light). Download in background.
5. "Pick a hotkey": default = hold Right Option. User can rebind.
6. Done — menu bar icon appears, window closes.

### Dictation (the main loop)
Default shortcut: **⌥ Space** (Option + Space), toggle-style.

1. User presses ⌥Space in any app → recording starts.
2. Menu bar icon turns red, faint sound cue (optional).
3. Audio captured to in-memory buffer.
4. User presses ⌥Space again → recording stops.
5. Buffer sent to active engine → text returned.
6. Text injected as keystrokes into focused app.
7. Menu bar icon back to idle.

### Switching model
- Click menu bar icon → submenu lists downloaded models with checkmark on active.
- Or open Settings → Models tab → radio select.

---

## Tech stack

- **Language**: Swift 5.10+
- **UI**: SwiftUI + AppKit interop where needed (NSStatusItem, NSWindow for settings)
- **Min macOS**: 14.0 (Sonoma) — required by FluidAudio + WhisperKit recent versions
- **Dependencies** (SPM):
  - `argmaxinc/WhisperKit` — Whisper on Neural Engine
  - `FluidInference/FluidAudio` — Parakeet on Neural Engine
- **Audio**: AVFoundation (AVAudioEngine)
- **Hotkey**: Carbon (RegisterEventHotKey) — only reliable way for global hotkeys on macOS
- **Keystroke output**: CoreGraphics (CGEvent)
- **Persistence**: UserDefaults for settings, Application Support dir for models

---

## Implementation phases

### Phase 1 — Skeleton (day 1)
- [x] Research models
- [x] PLAN.md
- [ ] Xcode project shell (user creates)
- [ ] Configure as menu-bar app (LSUIElement, no dock icon, no main window)
- [ ] Info.plist: NSMicrophoneUsageDescription
- [ ] Add SPM packages: WhisperKit, FluidAudio
- [ ] App compiles and shows a menu bar icon

### Phase 2 — Core pipeline (day 2)
- [ ] `TranscriptionEngine` protocol
- [ ] `WhisperKitEngine` — load model, transcribe buffer
- [ ] `FluidAudioEngine` — load Parakeet, transcribe buffer
- [ ] `ModelRegistry` (static catalog + active model state)
- [ ] `ModelDownloader` with progress
- [ ] `AudioRecorder` (AVAudioEngine → 16kHz mono Float)
- [ ] Smoke test: hardcoded WAV file → text printed to console

### Phase 3 — Dictation loop (day 3)
- [ ] `HotkeyManager` (Carbon, hold-to-talk, default Right Option)
- [ ] `KeystrokeOutput` (CGEvent unicode injection)
- [ ] `DictationController` glue
- [ ] Manual test: hold hotkey in TextEdit, see text appear

### Phase 4 — UI (day 4)
- [ ] Menu bar icon with recording state
- [ ] Settings window: General, Models, Hotkey tabs
- [ ] Models tab: list, download, delete, set active, disk usage
- [ ] Hotkey tab: rebind UI

### Phase 5 — Onboarding (day 5)
- [ ] First-launch detection
- [ ] Welcome → mic permission → accessibility permission → model picker → done
- [ ] Permission status checks throughout app

### Phase 6 — Polish & test
- [ ] App icon
- [ ] Launch at login (ServiceManagement)
- [ ] End-to-end test with multiple models
- [ ] Test on cold-boot Mac (clean perms)
- [ ] Handle edge cases: no mic, model not downloaded, transcription failure

### Future (post-v1)
- Cloud backend (Groq Whisper API) as opt-in
- Live streaming mode (WhisperKit supports it)
- Custom vocabulary / prompts per app
- Multiple hotkeys for different modes (e.g. one for code-formatted output)
- Word-level timestamps view
- Distribution: notarize + DMG / Homebrew cask

---

## Open questions

1. **Default hotkey** — **Option + Space**, toggle-style (press to start, press again to stop). Rebindable in Settings.
2. **Sandboxing** — Sandboxed apps can't easily inject keystrokes into other apps. **Decision: ship non-sandboxed for v1.** Means no Mac App Store distribution; we'll do direct download + notarization.
3. **Model auto-update** — Should we check for newer model versions? **Decision: no for v1, manual delete + redownload.**
4. **What if no model downloaded** — Show inline error in menu bar + open Settings. **Decision: yes.**

---

## Risks

| Risk | Mitigation |
|---|---|
| WhisperKit / FluidAudio API churn | Pin to specific versions in Package.resolved |
| Accessibility permission denied | Detect, show inline banner in menu, deep-link to settings |
| Audio device changes mid-recording | AVAudioEngine handles rerouting; test by unplugging headphones |
| Large model downloads on metered connection | Show size clearly, warn over 1 GB |
| Keystroke injection into password fields | macOS blocks this — document as known limitation |
