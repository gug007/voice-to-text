import {
  AI_TEXT_MODEL,
  APP_REQUIREMENTS,
  BUILT_IN_ACTIONS,
  CATALOG_SNAPSHOT,
  cloudModels,
  defaultModel,
  formatPrice,
  formatQuality,
  joinNames,
  liveOnStopModelNames,
  liveTextModelNames,
  localModels,
  MODEL_CATALOG,
  QUALITY_SCORE_SOURCES,
  type ModelFact,
  WHISPER_OFFLINE_NOTE,
} from "@/lib/app-facts";
import { DMG_URL, INTEGRATION_URL, RELEASES_URL, REPO_URL, SITE_URL } from "@/lib/constants";
import { PAGES, pageUrl, type PagePath } from "@/lib/pages";

// /llms.txt (https://llmstxt.org): a plain-text brief for AI assistants that
// answer questions about VoiceToText. Models, actions, requirements, routes and
// URLs come from lib/app-facts.ts, lib/pages.ts and lib/constants.ts so this
// file can't drift from the site. The prose restates the verified app facts,
// including what the app does NOT do, so answers don't overclaim.

export const dynamic = "force-static";

// `satisfies` makes a new route in PAGES fail the type check until it has a line here.
const PAGE_SUMMARIES = {
  "/": ["Home", "What VoiceToText does, the model catalog, FAQ and download."],
  "/how-to-use-voice-to-text-on-mac": [
    "How to use voice to text on Mac",
    "Install, permissions, the shortcut, review panel and settings, step by step.",
  ],
  "/meeting-recording": [
    "Meeting recording (Conversations)",
    "Recording mic + system audio, file uploads, speaker labels and AI summaries.",
  ],
  "/offline-speech-to-text-mac": [
    "Offline speech to text for Mac",
    "What stays on the Mac with local models and what uses the network.",
  ],
  "/voice-to-text-for-coding": [
    "Voice to text for coding",
    "Dictating prompts into Claude Code, Codex, Cursor, VS Code and terminals.",
  ],
  "/whisper-vs-parakeet-mac": [
    "Whisper vs. Parakeet on Mac",
    "Choosing between the local models: languages, quality scores and download size.",
  ],
  "/apple-dictation-alternative": [
    "Apple Dictation alternative",
    "How VoiceToText differs from the dictation built into macOS.",
  ],
  "/superwhisper-alternative": [
    "Superwhisper alternative",
    "VoiceToText compared with Superwhisper, with sources.",
  ],
  "/wispr-flow-alternative": [
    "Wispr Flow alternative",
    "VoiceToText compared with Wispr Flow, with sources.",
  ],
  "/granola-alternative": [
    "Granola alternative",
    "VoiceToText's Conversations compared with Granola for meeting notes, with sources.",
  ],
  "/macwhisper-alternative": [
    "MacWhisper alternative",
    "VoiceToText compared with MacWhisper, with sources.",
  ],
  "/compare": ["Comparisons", "Index of every VoiceToText comparison page."],
  "/compare/best-dictation-apps-for-mac": [
    "Best dictation apps for Mac",
    "A sourced comparison of Mac dictation apps, including VoiceToText.",
  ],
} as const satisfies Record<PagePath, readonly [name: string, summary: string]>;

function modelLine(model: ModelFact): string {
  const tags = [
    model.isDefault ? "default" : null,
    model.live ? "LIVE" : null,
    model.diarize ? "speaker labels" : null,
  ].filter(Boolean);
  const name = tags.length > 0 ? `${model.name} (${tags.join(", ")})` : model.name;
  const where = model.isLocal
    ? `on this Mac, free, ${model.worksOffline ? "works with the network off" : "needs a connection to load"}`
    : `${model.provider}, ${formatPrice(model)}`;
  return `- ${name} — ${where}, ${model.languagesInApp}, quality ${formatQuality(model)}/10. ${model.bestFor}`;
}

function list(items: readonly string[]): string {
  return items.map((item) => `- ${item}`).join("\n");
}

function buildLlmsTxt(): string {
  const local = localModels();
  const cloud = cloudModels();
  const fallback = defaultModel();
  const diarize = MODEL_CATALOG.filter((m) => m.diarize).map((m) => m.name);
  const pages = (Object.keys(PAGES) as PagePath[]).map((path) => {
    const [name, summary] = PAGE_SUMMARIES[path];
    return `- [${name}](${pageUrl(path)}): ${summary}`;
  });

  return `# VoiceToText

> VoiceToText is a free dictation and meeting-transcription app for Mac (${APP_REQUIREMENTS.short}). Press a global shortcut, speak, review the text, and it is pasted into whatever app you were using. By default it transcribes on the Mac with the local ${fallback.name} model, which works with the network off once downloaded; OpenAI and ElevenLabs models are optional and use your own API key. It also records conversations (your microphone plus system audio), transcribes audio and video files, and keeps a searchable local history. No account, no paid tier; the source is available on GitHub.

Facts below describe ${CATALOG_SNAPSHOT}.

## Basics

- Price: free. No paid tier, no subscription, no VoiceToText account.
- Source: available on GitHub at ${REPO_URL}. The repository has no license file, so describe it as "source available", not "open source".
- Requirements: ${APP_REQUIREMENTS.os}; ${APP_REQUIREMENTS.processor}. Builds are Apple Silicon only.
- Download: ${DMG_URL} (signed and notarized DMG). All releases: ${RELEASES_URL}
- Website: ${SITE_URL}
- App shape: a regular Mac window (panes: General, Conversations, History, Shortcut, Models, Actions, Cloud, Updates) with a Dock icon, plus a menu bar item. Menu-bar-only is optional (turn off "Show in Dock"). Launch at login is on after first run. Appearance: System, Light or Dark.
- Permissions: Microphone; Accessibility (required to start recording and to paste); Input Monitoring only when Right Control alone is the shortcut; Screen Recording only for Conversations, to capture system audio (the screen is never recorded).

## Dictation

- Default shortcut Option+Space (⌥Space), press to toggle. "Hold to record" is optional. The shortcut can be any key with a modifier, a lone F1–F20 key, or Right Control alone.
- While recording, a floating card shows a level meter, elapsed time, and Cancel (Esc) / Finish.
- "Review before pasting" is on by default: Return pastes, Shift+Return adds a new line, pressing the shortcut again pastes, Esc cancels, ⌘R records another take inserted at the cursor. With review off, text is pasted as soon as you stop.
- Output is a paste, not typing: the clipboard is saved, the text is pasted with a synthetic ⌘V, and the previous clipboard is restored about 0.25 s later. It works wherever ⌘V pastes text; fields that block pasting won't receive it.
- If the microphone changes mid-take (for example AirPods switching profile), capture restarts automatically; otherwise the audio captured so far is still transcribed. Failed transcriptions keep the audio for Retry.

## AI actions (optional)

${list(BUILT_IN_ACTIONS)}
- Plus custom actions (a name and an instruction).
- Shown in the review panel, run manually per dictation (click or ⌘1–⌘9), with Undo. Never automatic.
- All off by default. They need an OpenAI API key and send the transcript text to OpenAI (${AI_TEXT_MODEL}).

## Conversations (meeting recording)

- Records your microphone plus system audio (the other people on Zoom, Meet, Teams, FaceTime, Webex, Discord or any app that plays audio). No bot joins the call.
- Start from the Conversations pane, the menu bar, or an optional Conversation shortcut (no default key; press to start, press again to stop).
- Transcribed after you stop, not live. Recordings over 12 minutes are split at quiet points into roughly 10-minute segments.
- Upload File… or drag one audio or video file that macOS can read (MP3, M4A, WAV, AIFF, FLAC, MP4, MOV and similar). Uses the Conversations transcription model, which is on-device by default. History keeps the extracted audio, not the original video.
- Conversations have their own transcription model setting (default: same as dictation); live models are not available there.
- Speaker labels ("Speaker 1", "Speaker 2"…) only with the cloud model ${diarize.join(", ")}. Rename them with "Name speakers". Local models do not separate speakers.
- If the app quits mid-recording, the audio appears in History on the next launch, untranscribed; use Regenerate.

## History and AI insights

- Every dictation (audio and transcript) and every conversation or upload is saved locally in ~/Library/Application Support/VoiceToText/History. The "Save recordings" toggle stops saving dictations; conversations and uploads are always saved. Newest 200 recordings are kept, favorites included in the count.
- Search across transcripts, earlier versions, summaries, action items, custom results, speaker names, model, type and date. Favorites, playback, copy, delete with 5-second Undo, Clear All.
- Regenerate any recording with another model; every version is kept side by side.
- AI insights on any recording: Summary, Action Items (checklist with owner and due date only when said), and up to 3 custom-prompt results. They need an OpenAI API key and send the transcript text (with speaker names) to OpenAI (${AI_TEXT_MODEL}).

## Models

${MODEL_CATALOG.length} models: ${local.length} local and ${cloud.length} cloud. ${QUALITY_SCORE_SOURCES}

On this Mac (downloaded once from Hugging Face; audio stays on the Mac). ${WHISPER_OFFLINE_NOTE}
${local.map(modelLine).join("\n")}

Cloud (your own API key; audio goes directly from the Mac to the provider, which bills you at its list price):
${cloud.map(modelLine).join("\n")}

- LIVE models are for dictation only. With ${joinNames(liveTextModelNames("word by word"))}, text appears word by word as you speak. With ${joinNames(liveTextModelNames("phrase by phrase"))}, OpenAI transcribes each phrase after a short pause (about half a second), so text appears phrase by phrase. With ${joinNames(liveOnStopModelNames())}, the text appears only when you stop.
- Languages: ${fallback.name} covers ${fallback.languagesInApp}, detected automatically. Local Whisper models transcribe English only in VoiceToText (there is no language picker). For other languages use a cloud model: OpenAI models cover 99+ languages and ElevenLabs Scribe 90+, detected automatically.

## Privacy and network

- With local models and no API keys, the app connects only to Hugging Face (each model downloads once, and loading a Whisper model, after each launch, needs a connection to it) and GitHub Releases (update check at launch and every 24 hours). Audio and transcripts stay on the Mac. With Parakeet, the default, transcription works fully offline.
- Cloud transcription models send audio to OpenAI or ElevenLabs. AI actions and AI insights send transcript text to OpenAI. Adding an API key sends one verification request to that provider.
- API keys are stored in the app's preferences (UserDefaults) on the Mac, not in the Keychain.
- No VoiceToText servers, no accounts, and no analytics or telemetry in the app. The website uses Google Analytics.
- Updates are never silent: the app offers Install Update, Later or Skip This Version.

## Automation

- URL scheme: voicetotext://toggle, voicetotext://start, voicetotext://stop, voicetotext://cancel (for example \`open -g voicetotext://toggle\`) for Raycast, Shortcuts, Stream Deck and scripts. Dictation only. Details: ${INTEGRATION_URL}

## Not supported

- Intel Macs, or macOS versions before ${APP_REQUIREMENTS.minMacOS}.
- iPhone, iPad, Windows, Linux or a web app.
- Voice commands or spoken punctuation ("new line", "comma" are written as words), built-in filler-word removal, custom vocabulary, or a language picker.
- Live transcript during Conversations, pausing a conversation, automatic meeting detection, calendar integration, or meeting-app plugins.
- On-device speaker identification, or recognising speakers by name.
- Export or sharing of transcripts (copy to clipboard only), transcript editing in History, iCloud sync, or playback scrubbing.
- Sounds, notifications, or a microphone picker (the macOS default input is used).
- A local AI model for actions or insights, or a choice of AI model for them.

## Key pages

${pages.join("\n")}

## Optional

- [Source code](${REPO_URL}): the app's Swift source.
- [Integration guide](${INTEGRATION_URL}): triggering dictation from other apps with the URL scheme.
- [Releases](${RELEASES_URL}): release notes and downloads.
`;
}

export function GET(): Response {
  return new Response(buildLlmsTxt(), {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
