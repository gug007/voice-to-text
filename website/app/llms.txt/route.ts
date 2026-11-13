import {
  AI_TEXT_MODEL,
  APP_REQUIREMENTS,
  BUILT_IN_ACTIONS,
  CATALOG_SNAPSHOT,
  CLOUD_PROVIDERS_AND,
  CLOUD_PROVIDERS_OR,
  cloudModels,
  CONVERSATION_HUD_DEFAULT,
  CONVERSATION_HUD_SETTINGS,
  defaultModel,
  DICTATION_HUD_SIZES,
  formatPrice,
  formatQuality,
  joinNames,
  liveOnStopModelNames,
  liveTextModelNames,
  localModels,
  MICROPHONE_SETTING,
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
  "/": ["Home", "What VoiceToText does (dictation, meeting recording, history), the full model catalog with prices and quality scores, FAQ and download."],
  "/how-to-use-voice-to-text-on-mac": [
    "How to use voice to text on Mac",
    "Turning on the built-in Mac Dictation and its shortcut, then VoiceToText's install, permissions, shortcut, review panel and settings, step by step.",
  ],
  "/meeting-recording": [
    "Meeting recording (Conversations)",
    "Recording a call's mic + system audio with no bot, file uploads, the transcription model, speaker labels and AI summaries.",
  ],
  "/record-meetings-without-a-bot-mac": [
    "Record Zoom, Google Meet and Teams calls without a bot",
    "How on-Mac capture (mic + system audio via ScreenCaptureKit) works in each call app, host or participant; a meeting bot compared with on-Mac recording; what other participants see; consent.",
  ],
  "/free-meeting-recorder-mac": [
    "Free meeting recorder for Mac",
    "What is free (recording, local transcription, history, search; no account, trial or minute cap) and what costs money (cloud models, speaker labels, AI summaries, billed to your own API key), with per-hour list prices.",
  ],
  "/offline-speech-to-text-mac": [
    "Offline speech to text for Mac",
    "What stays on the Mac with local models, what uses the network, and how to check it.",
  ],
  "/voice-to-text-for-coding": [
    "Voice to text for coding",
    "Dictating prompts into Claude Code, Codex, Cursor, VS Code and terminals.",
  ],
  "/whisper-vs-parakeet-mac": [
    "Whisper vs. Parakeet on Mac",
    "Choosing between the local models: languages, published word error rates, quality scores and download size.",
  ],
  "/apple-dictation-alternative": [
    "Apple Dictation alternative",
    "How VoiceToText differs from the dictation built into macOS: review before paste, model choice, meetings and history.",
  ],
  "/superwhisper-alternative": [
    "Superwhisper alternative",
    "Who should stay with Superwhisper and who might switch: platforms, local vs cloud models, AI formatting, price, and other Superwhisper alternatives, from vendor sources.",
  ],
  "/wispr-flow-alternative": [
    "Wispr Flow alternative",
    "VoiceToText (on-device by default) compared with Wispr Flow (cloud dictation): privacy, price, platforms and features, from vendor sources.",
  ],
  "/granola-alternative": [
    "Granola alternative",
    "Granola compared with VoiceToText's Conversations for meetings: where audio is processed, what stays on the Mac, platforms, price, and the source-available question, from vendor sources.",
  ],
  "/macwhisper-alternative": [
    "MacWhisper alternative",
    "Who should stay with MacWhisper (file transcription, exports, subtitles) and who might switch (dictation, meetings), plus other MacWhisper alternatives, from vendor sources.",
  ],
  "/dragon-for-mac-alternative": [
    "Dragon for Mac alternative",
    "What replaced the discontinued Dragon for Mac (Apple Dictation, Voice Control, VoiceToText), with sources. VoiceToText is not a medical dictation product.",
  ],
  "/compare": ["Comparisons", "Index of every VoiceToText comparison page, by vendor."],
  "/compare/best-dictation-apps-for-mac": [
    "Best dictation apps for Mac",
    "A sourced comparison of seven Mac dictation apps, including VoiceToText, on dictation, files, meetings, privacy, languages and price.",
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
  const priceNotes = [...new Set(cloud.flatMap((m) => (m.priceNote ? [m.priceNote] : [])))];
  const pages = (Object.keys(PAGES) as PagePath[]).map((path) => {
    const [name, summary] = PAGE_SUMMARIES[path];
    return `- [${name}](${pageUrl(path)}): ${summary}`;
  });

  return `# VoiceToText

> VoiceToText is a free, local-first dictation and meeting-transcription app for Mac (${APP_REQUIREMENTS.short}). Press a global shortcut, speak, review the text, and it is pasted into whatever app you were using. It offers ${MODEL_CATALOG.length} transcription models: by default it transcribes on the Mac with the local ${fallback.name} model, which works with the network off once downloaded, and ${local.length - 1} more local models are available; ${cloud.length} ${CLOUD_PROVIDERS_AND} cloud models are optional and use your own API key. It also records meetings and calls (your microphone plus system audio, with no bot joining the call), transcribes audio and video files, and keeps a searchable local history. No account, no paid tier; the source is available on GitHub, though not under an open-source license.

Facts below describe ${CATALOG_SNAPSHOT}.

## Basics

- Price: free. No paid tier, no subscription, no VoiceToText account.
- Source: available on GitHub at ${REPO_URL}. The repository has no license file, so describe it as "source available", not "open source".
- Requirements: ${APP_REQUIREMENTS.os}; ${APP_REQUIREMENTS.processor} (one universal build). Local models run much faster on Apple Silicon than on Intel; on Intel they run through transcribe.cpp, on the graphics card when it works and on the CPU otherwise.
- Download: ${DMG_URL} (DMG containing a signed, notarized app). All releases: ${RELEASES_URL}
- Website: ${SITE_URL}
- App shape: a regular Mac window (panes: General, Conversations, History, Shortcut, Models, Actions, Cloud, Updates) with a Dock icon, plus a menu bar item. Menu-bar-only is optional (turn off "Show in Dock"). Launch at login is on after first run. Appearance: System, Light or Dark.
- Permissions: Microphone; Accessibility (required to start recording and to paste); Input Monitoring only when Right Control alone is the shortcut; Screen Recording only for Conversations, to capture system audio (the screen is never recorded).

## Dictation

- Default shortcut Option+Space (⌥Space), press to toggle. "Hold to record" is optional. The shortcut can be any key with a modifier, a lone F1–F20 key, or Right Control alone.
- While recording, a floating HUD shows a level meter, the elapsed time, and Cancel (Esc) / Finish. Settings → General → Recording HUD sets its size: ${DICTATION_HUD_SIZES.map(({ size, isDefault, looks }) => `${size}${isDefault ? " (default)" : ""}: ${looks}`).join("; ")}. Only Large shows text while you speak. The review panel is the same at every size.
- "Review before pasting" is on by default: Return pastes, Shift+Return adds a new line, pressing the shortcut again pastes, Esc cancels, ⌘R records another take inserted at the cursor. With review off, text is pasted as soon as you stop.
- Output is a paste, not typing: the clipboard is saved, the text is pasted with a synthetic ⌘V, and the previous clipboard is restored about 0.25 s later. It works wherever ⌘V pastes text; fields that block pasting won't receive it.
- Microphone: ${MICROPHONE_SETTING}
- If the microphone changes mid-take (for example AirPods switching profile), capture restarts automatically; otherwise the audio captured so far is still transcribed. Failed transcriptions keep the audio for Retry.

## AI actions (optional)

${list(BUILT_IN_ACTIONS)}
- Plus custom actions (a name and an instruction).
- Shown in the review panel, run manually per dictation (click or ⌘1–⌘9), with Undo. Never automatic.
- All off by default. They need an OpenAI API key and send the transcript text to OpenAI (${AI_TEXT_MODEL}).

## Conversations (meeting recording)

- Records your microphone plus system audio (the other people on Zoom, Meet, Teams, FaceTime, Webex, Discord or any app that plays audio). No bot joins the call.
- Works the same whether the user hosts or joins the call, in the meeting app or a browser: it doesn't use the meeting app's own recording, and nothing is installed in Zoom, Meet or Teams. Everything the Mac plays is recorded except VoiceToText's own sound.
- VoiceToText notifies no one that a call is being recorded, so telling participants and following consent laws is the user's responsibility. The Recording HUD may show in a screen share.
- If macOS stops the capture or the disk fills up mid-recording, everything captured up to then is saved and transcribed.
- Start from the Conversations pane, the menu bar, or an optional Conversation shortcut (no default key; press to start, press again to stop).
- While a conversation records, a floating Recording HUD sits at the top centre of the screen with a level meter, the running clock, and one button: Stop & Transcribe. It has no Cancel; Cancel stays in the Conversations pane. It can be dragged, and it stays up through transcription (Medium and Large show progress such as 3/12 on long recordings). Settings → Conversations → Recording HUD: ${CONVERSATION_HUD_SETTINGS.join(", ")} (default ${CONVERSATION_HUD_DEFAULT}); Off hides it, leaving the menu bar's running clock.
- Transcribed after you stop, not live. Recordings over 12 minutes are split at quiet points into roughly 10-minute segments.
- Upload File… or drag one audio or video file that macOS can read (MP3, M4A, WAV, AIFF, FLAC, MP4, MOV and similar). Uses the Conversations transcription model, which is on-device by default. History keeps the extracted audio, not the original video.
- Conversations have their own transcription model setting (default: same as dictation); live models are not available there.
- Speaker labels ("Speaker 1", "Speaker 2"…) only with the cloud model ${diarize.join(", ")}. Rename them with "Name speakers". Local models do not separate speakers.
- If the app quits mid-recording, the audio appears in History on the next launch, untranscribed; use Regenerate.

## History and AI insights

- Every dictation (audio and transcript) and every conversation or upload is saved locally in ~/Library/Application Support/VoiceToText/History. The "Save recordings" toggle stops saving dictations; conversations and uploads are always saved. The newest 200 dictations are kept; favorites, conversations, uploads, and recordings with a summary, action items, custom result or speaker names are never removed automatically.
- Search across transcripts, earlier versions, summaries, action items, custom results, speaker names, model, type and date. Favorites, playback, copy, delete with 5-second Undo, Clear All.
- Regenerate any recording with another model; every version is kept side by side.
- AI insights on any recording: Summary, Action Items (checklist with owner and due date only when said), and up to 3 custom-prompt results. They need an OpenAI API key and send the transcript text (with speaker names) to OpenAI (${AI_TEXT_MODEL}).

## Models

${MODEL_CATALOG.length} models: ${local.length} local and ${cloud.length} cloud. ${QUALITY_SCORE_SOURCES}

On this Mac (downloaded once from Hugging Face; audio stays on the Mac). ${WHISPER_OFFLINE_NOTE}
${local.map(modelLine).join("\n")}

Cloud (your own API key; audio goes directly from the Mac to the provider, which bills you at its list price${priceNotes.length > 0 ? `; ${priceNotes.join(" ")}` : ""}):
${cloud.map(modelLine).join("\n")}

- LIVE models are for dictation only, and their text shows while you speak only in the Large recording HUD; with Small (the default) or Medium it appears when you stop. In the Large HUD, ${joinNames(liveTextModelNames("word by word"))} shows text word by word as you speak. With ${joinNames(liveTextModelNames("phrase by phrase"))}, OpenAI transcribes each phrase after a short pause (about half a second), so text appears phrase by phrase. With ${joinNames(liveOnStopModelNames())}, the text appears only when you stop.
- Languages: ${fallback.name} covers ${fallback.languagesInApp}, detected automatically. Local Whisper models cover 99 languages, also detected automatically (once per recording, or per 10-minute part of a longer one, from its first speech; there is no language picker), most accurately in English and other major languages. For a language outside ${fallback.name}'s 25, use a Whisper model or a cloud model: OpenAI models cover 99+ languages, Groq's Whisper models 99 and ElevenLabs Scribe 90+, detected automatically.

## Privacy and network

- With local models and no API keys, the app connects only to Hugging Face (each model downloads once) and GitHub Releases (update check at launch and every 24 hours). Audio and transcripts stay on the Mac. Once a local model has downloaded, transcription works fully offline.
- A cloud transcription model sends audio to its provider (${CLOUD_PROVIDERS_OR}). AI actions and AI insights send transcript text to OpenAI. Adding an API key sends one verification request to that provider.
- API keys are stored in the macOS login Keychain on the Mac (older versions kept them in the app's preferences and move them to the Keychain on first launch).
- No VoiceToText servers, no accounts, and no analytics or telemetry in the app. The website uses Google Analytics.
- Updates are never silent: the app offers Install Update, Later or Skip This Version.

## Automation

- URL scheme: voicetotext://toggle, voicetotext://start, voicetotext://stop, voicetotext://cancel (for example \`open -g voicetotext://toggle\`) for Raycast, Shortcuts, Stream Deck and scripts. Dictation only. Details: ${INTEGRATION_URL}

## Not supported

- macOS versions before ${APP_REQUIREMENTS.minMacOS}.
- iPhone, iPad, Windows, Linux or a web app.
- Voice commands or spoken punctuation ("new line", "comma" are written as words), built-in filler-word removal, custom vocabulary, or a language picker.
- Live transcript during Conversations, pausing a conversation, automatic meeting detection, calendar integration, or meeting-app plugins.
- On-device speaker identification, or recognising speakers by name.
- Export or sharing of transcripts (copy to clipboard only), transcript editing in History, iCloud sync, or playback scrubbing.
- Sounds or notifications.
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
