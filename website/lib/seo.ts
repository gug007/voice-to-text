import {
  AUTHOR_URL,
  DMG_URL,
  GUIDE_URL,
  REPO_URL,
  SITE_URL,
} from "./constants";

export const SOFTWARE_ID = `${SITE_URL}/#software`;
export const WEBSITE_ID = `${SITE_URL}/#website`;
export const PERSON_ID = `${SITE_URL}/#creator`;
export const HOME_PAGE_ID = `${SITE_URL}/#webpage`;

// This describes the product entity. Do not add aggregateRating/review until
// a genuine review is visible on the page and can be represented faithfully.
export const softwareApplicationJsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "@id": SOFTWARE_ID,
  name: "VoiceToText",
  alternateName: "VoiceToText for Mac",
  description:
    "Free, open-source voice to text and speech to text app for Mac. Press a hotkey in any app, speak, and your words are typed at the cursor — transcribed offline on the Apple Neural Engine, with optional OpenAI and ElevenLabs cloud models, live streaming transcription, one-click AI transcript actions, and meeting recording.",
  keywords:
    "voice to text mac, speech to text mac, mac dictation, dictation app for mac, offline speech recognition mac, free voice to text, real-time transcription mac, whisper mac app",
  url: `${SITE_URL}/`,
  sameAs: REPO_URL,
  downloadUrl: DMG_URL,
  installUrl: DMG_URL,
  softwareHelp: { "@id": `${GUIDE_URL}#webpage` },
  applicationCategory: "UtilitiesApplication",
  applicationSubCategory: "Speech to Text",
  operatingSystem: "macOS 26.4 or later",
  processorRequirements: "Apple Silicon (M1 or newer)",
  offers: {
    "@type": "Offer",
    price: 0,
    priceCurrency: "USD",
    availability: "https://schema.org/InStock",
  },
  isAccessibleForFree: true,
  author: {
    "@id": PERSON_ID,
  },
  mainEntityOfPage: { "@id": HOME_PAGE_ID },
  image: `${SITE_URL}/opengraph-image`,
  featureList: [
    "Voice to text on Mac with a global hotkey (Option+Space by default) — press to toggle or hold to record, fully customizable including Right Control",
    "Speech to text that runs offline on-device after a one-time model download, accelerated by the Apple Neural Engine",
    "Six local models: Parakeet TDT v3 (FluidAudio) and Whisper Large v3 Turbo, Large v3, Small, Base, Tiny (WhisperKit)",
    "Five optional cloud models across OpenAI (GPT-4o Transcribe, GPT-4o Transcribe Realtime, GPT-4o Mini Transcribe, Whisper-1) and ElevenLabs (Scribe v2 Realtime)",
    "Real-time streaming transcription — words appear live as you speak with Scribe v2 Realtime or GPT-4o Transcribe Realtime",
    "Review before pasting: edit the transcript in a floating panel, then confirm — or turn review off for instant paste",
    "One-click AI actions on the transcript: Clean transcript, To English, Improve prompt, Fix grammar, Summarize, Essentials only, plus your own custom actions",
    "Resume dictation at the caret to append to a take",
    "Types transcribed text into any focused macOS app",
    "Record meetings and conversations — captures your microphone plus system audio in the background via ScreenCaptureKit",
    "Long recordings transcribed in segments; interrupted recordings are recovered on next launch",
    "Rolling on-device recording history (200 most recent) with audio playback and favorites — deletes come with an undo",
    "Regenerate any transcript with a different model and keep both versions side by side to compare",
    "Import existing audio or video files and transcribe them on-device",
    "Automate dictation from any app via the voicetotext:// URL scheme",
    "Built-in updater installs new versions straight from GitHub Releases",
    "Native SwiftUI app for Mac — no Electron",
  ],
} as const;

export const websiteJsonLd = {
  "@context": "https://schema.org",
  "@type": "WebSite",
  "@id": WEBSITE_ID,
  name: "VoiceToText",
  alternateName: "voicetotext.cc",
  url: `${SITE_URL}/`,
  inLanguage: "en",
  publisher: { "@id": PERSON_ID },
  about: { "@id": SOFTWARE_ID },
} as const;

export const homePageJsonLd = {
  "@context": "https://schema.org",
  "@type": "WebPage",
  "@id": HOME_PAGE_ID,
  url: `${SITE_URL}/`,
  name: "Voice to Text for Mac — Free, Offline",
  description:
    "Free voice to text for Mac that types into any app from a hotkey, runs offline on Apple Silicon, needs no account, and is open source.",
  isPartOf: { "@id": WEBSITE_ID },
  mainEntity: { "@id": SOFTWARE_ID },
  primaryImageOfPage: {
    "@type": "ImageObject",
    url: `${SITE_URL}/opengraph-image`,
    width: 1200,
    height: 630,
  },
  inLanguage: "en",
} as const;

type FaqEntry = { question: string; answer: string };

// KEEP IN SYNC with the visible FAQ in components/sections/faq.tsx — Google
// requires FAQPage JSON-LD to match on-page content. Edit both together.
const faqEntries: FaqEntry[] = [
  {
    question: "Is VoiceToText free?",
    answer:
      "Yes — completely free, forever. VoiceToText is free and open source, with the full source code on GitHub. No paid tiers, no accounts, and no in-app purchases.",
  },
  {
    question: "Does it work offline? Is my voice data sent anywhere?",
    answer:
      "Yes, transcription works fully offline by default. Local models (Whisper, Parakeet) run on the Apple Neural Engine — your audio never leaves your Mac. The app's only network traffic is one-time model downloads and a daily update check against GitHub Releases. Cloud models are strictly opt-in: audio is sent directly to the provider (OpenAI or ElevenLabs) under your own API key only when you explicitly select a cloud engine, and AI transcript actions use your OpenAI key the same way. VoiceToText itself never receives your audio.",
  },
  {
    question: "How do I use voice to text on my Mac?",
    answer:
      "Install from the DMG, grant Microphone and Accessibility permissions, then press Option+Space in any app, speak, and press it again. The transcript pops up for a quick review — hit Return and it's pasted at the cursor. Prefer zero friction? Turn review off in Settings and text lands instantly. Prefer hold-to-talk? Switch the shortcut to hold-to-record. Works identically on MacBook Air, MacBook Pro, iMac, Mac mini, and Mac Studio.",
  },
  {
    question: "Can I review or edit the transcript before it types?",
    answer:
      "Yes — that's the default. After you stop speaking, the transcript appears in a small floating panel where you can edit it, run one-click AI actions on it, resume dictating at the caret (Cmd+R), paste it (Return), or discard it (Esc). Nothing types until you confirm. If you'd rather have text pasted immediately, switch off 'Review before pasting' in Settings.",
  },
  {
    question: "Can it clean up, translate, or summarize what I said?",
    answer:
      "Yes. AI Actions appear as one-click buttons in the review panel (with Cmd+1–9 shortcuts): Clean transcript, To English, Improve prompt, Fix grammar, Summarize, and Essentials only are built in, and you can write your own custom actions. Actions run with your own OpenAI API key and every transform can be undone before you paste.",
  },
  {
    question: "Why does it need Accessibility permission?",
    answer:
      "Accessibility permission is how macOS lets one app type into another. VoiceToText uses it to paste transcribed text at the cursor, register the global shortcut, and catch Esc so you can cancel a recording — it does not log your keystrokes, read your screen, or access any other app's data. (Only the optional Right Control shortcut needs the separate Input Monitoring permission.) The source code is public if you want to verify exactly how the permissions are used.",
  },
  {
    question: "What are the system requirements?",
    answer:
      "The current builds require macOS 26.4 or later and an Apple Silicon Mac (M1 or newer). Intel Macs are not supported because the local models rely on the Apple Neural Engine. Cloud models work on any supported Mac with an internet connection.",
  },
  {
    question: "How accurate is it? Which models does it use?",
    answer:
      "You choose from six local models: Parakeet TDT v3 is the fastest on-device option, Whisper Large v3 is the most accurate offline option, and Whisper Large v3 Turbo is the best balance — plus Small, Base, and Tiny for older or space-constrained Macs. For the highest accuracy across accents and technical jargon, bring your own API key and switch to GPT-4o Transcribe, GPT-4o Mini Transcribe, or Whisper-1 (OpenAI), or Scribe v2 Realtime (ElevenLabs) in Settings.",
  },
  {
    question: "Does it transcribe in real time?",
    answer:
      "Yes, with a streaming cloud model. Pick Scribe v2 Realtime (ElevenLabs) or GPT-4o Transcribe Realtime (OpenAI) and your words appear live in the recording HUD as you speak, then paste when you finish. If the streaming connection can't be opened, the app automatically falls back to transcribing the finished recording. Local models transcribe when you stop.",
  },
  {
    question: "How is VoiceToText different from Apple Dictation, Apple Intelligence, or Wispr Flow?",
    answer:
      "Apple Dictation is tied to Apple's servers for full quality. Apple Intelligence writing tools rewrite text after the fact — they are not dictation at the cursor. Wispr Flow is a paid subscription that always sends audio to the cloud. VoiceToText is free, open source, on-device by default, works as press-to-toggle or hold-to-talk, and lets you bring your own OpenAI or ElevenLabs key when you want maximum accuracy or live streaming.",
  },
  {
    question: "What languages are supported?",
    answer:
      "Whisper models support 99 languages out of the box. Parakeet TDT v3 covers 25 European languages plus Japanese and is the fastest local option. ElevenLabs Scribe v2 Realtime covers 90+ languages. The language is detected automatically — if you dictate in a language Parakeet doesn't cover, select a Whisper model in Settings → Models.",
  },
  {
    question: "What apps does VoiceToText work in?",
    answer:
      "Any Mac app with a text field. Apple Notes, Notion, Obsidian, Bear, Pages, Google Docs, Microsoft Word, Slack, Messages, Mail, Gmail, Outlook, WhatsApp, Discord, Safari and Chrome address bars, ChatGPT, Claude.ai — if macOS puts a cursor there, your voice types into it. No app-specific setup.",
  },
  {
    question: "Can I dictate into Claude Code, Cursor, or other AI coding tools?",
    answer:
      "Yes. VoiceToText types into whatever app has focus — Claude Code, Codex CLI, Cursor, Copilot Chat, ChatGPT, any terminal, any editor. Press the hotkey, speak your prompt, press again. The built-in 'Improve prompt' action can even restructure your spoken request into a clear AI prompt before you paste it. Developers can also trigger dictation from their own apps via the voicetotext:// URL scheme.",
  },
  {
    question: "Can VoiceToText record and transcribe meetings?",
    answer:
      "Yes. Alongside hotkey dictation, VoiceToText can record a full meeting or conversation — capturing your microphone and your Mac's system audio (the other participants in Zoom, Google Meet, Microsoft Teams, FaceTime, and any other app) in the background while you keep working. When you stop, it transcribes the recording with your chosen model — on-device by default — and saves the audio and transcript to your history. Recording system audio uses Apple's ScreenCaptureKit and requires Screen Recording permission (audio only — it never records the screen).",
  },
  {
    question: "Where are my recordings and transcripts stored?",
    answer:
      "Locally on your Mac, in Application Support — never uploaded. Dictations and meetings are saved with their audio and transcript to a rolling history (your 200 most recent recordings) you can play back, copy, favorite, or delete (deletes come with a 5-second undo). Saving can also be switched off entirely. You can re-transcribe any recording with a different model and keep both versions to compare. With a local model, your audio never leaves the Mac.",
  },
  {
    question: "Do you collect any usage data or telemetry?",
    answer:
      "The app collects nothing: no accounts, no analytics, no first-party servers. With a local model your audio generates zero network traffic — the only connections the app makes are model downloads and an update check against GitHub Releases. If you opt in to a cloud model, audio goes directly from your Mac to the provider — VoiceToText is never in that path. The repo is public; verify it yourself or watch traffic with Little Snitch. (This website uses Google Analytics to count visits; the app itself contains no analytics code.)",
  },
];

export const faqPageJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "@id": `${SITE_URL}/#faq-page`,
  url: `${SITE_URL}/#faq`,
  isPartOf: { "@id": HOME_PAGE_ID },
  mainEntity: faqEntries.map(({ question, answer }) => ({
    "@type": "Question",
    name: question,
    acceptedAnswer: { "@type": "Answer", text: answer },
  })),
} as const;

export const personJsonLd = {
  "@context": "https://schema.org",
  "@type": "Person",
  "@id": PERSON_ID,
  name: "Gurgen Abagyan",
  url: AUTHOR_URL,
  sameAs: [AUTHOR_URL],
} as const;

/* ---------- Meeting recording page ---------- */

export const MEETING_PATH = "/meeting-recording";
export const MEETING_URL = `${SITE_URL}${MEETING_PATH}`;

export const meetingFaqEntries: FaqEntry[] = [
  {
    question: "Can I record and transcribe meetings on my Mac for free?",
    answer:
      "Yes. VoiceToText is free and open source. It records a meeting or conversation on your Mac and transcribes it on-device — no subscription, no account, and no per-minute fees. The same app also does hotkey dictation into any text field.",
  },
  {
    question: "Does it record the other participants, or just my microphone?",
    answer:
      "Both. VoiceToText captures your microphone and your Mac's system audio at the same time, so the people on the other end of a Zoom, Google Meet, Microsoft Teams, FaceTime, Webex, or Discord call are recorded along with you. System-audio capture uses Apple's ScreenCaptureKit, so it works with any app that plays sound — no meeting-specific plugin or bot in the call.",
  },
  {
    question: "Is meeting recording private? Does my audio stay on my Mac?",
    answer:
      "Yes. With a local model (Whisper or Parakeet on the Apple Neural Engine) the recording is transcribed entirely on-device and never leaves your Mac. The audio file and transcript are saved to a local history under Application Support. Cloud transcription is strictly opt-in: only if you choose an OpenAI or ElevenLabs model is audio sent — directly to that provider under your own API key.",
  },
  {
    question: "Which permissions does meeting recording need?",
    answer:
      "Two: Microphone (to record your voice) and Screen Recording (which is how macOS exposes system audio through ScreenCaptureKit — VoiceToText never records the screen, only the audio). Accessibility is only used by the dictation feature (typing at the cursor, the global shortcut, Esc to cancel) and is not needed to record meetings. You grant these once in System Settings and can revoke them anytime.",
  },
  {
    question: "What happens with long meetings — or if the app crashes mid-recording?",
    answer:
      "Long recordings are split into segments at the quietest moments and transcribed piece by piece with progress shown, so an hour-long call transcribes reliably. The audio streams straight to disk while recording, and if the app is interrupted — crash, force-quit, power loss — the recording is repaired and filed into your history on the next launch, so a long recording isn't lost.",
  },
  {
    question: "Can I transcribe an existing audio or video file?",
    answer:
      "Yes. Open Conversations and choose Upload File to drop in an existing recording — audio or video, in any common format. VoiceToText extracts the audio track, transcribes it on-device, and saves it to your history alongside your live recordings.",
  },
  {
    question: "Can I re-transcribe a recording with a more accurate model?",
    answer:
      "Yes. Every recording keeps its audio, so you can regenerate the transcript with a different engine — for example switch from fast on-device Parakeet to OpenAI GPT-4o Transcribe for a tricky recording. The new transcript becomes active and the previous one is kept as an alternate, so you can compare both and remove whichever you don't want.",
  },
];

export const meetingFaqPageJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "@id": `${MEETING_URL}#faq-page`,
  url: `${MEETING_URL}#faq`,
  isPartOf: { "@id": `${MEETING_URL}#webpage` },
  mainEntity: meetingFaqEntries.map(({ question, answer }) => ({
    "@type": "Question",
    name: question,
    acceptedAnswer: { "@type": "Answer", text: answer },
  })),
} as const;

export const meetingPageJsonLd = {
  "@context": "https://schema.org",
  "@type": "WebPage",
  "@id": `${MEETING_URL}#webpage`,
  name: "Record and transcribe meetings on Mac",
  description:
    "Free, open-source meeting recorder for Mac. Records your microphone and system audio together (Zoom, Google Meet, Teams, FaceTime) and transcribes the conversation on-device on the Apple Neural Engine — no bot in the call, no subscription.",
  url: MEETING_URL,
  isPartOf: { "@id": WEBSITE_ID },
  about: { "@id": SOFTWARE_ID },
  mainEntity: { "@id": SOFTWARE_ID },
  author: {
    "@id": PERSON_ID,
  },
  breadcrumb: { "@id": `${MEETING_URL}#breadcrumb` },
  primaryImageOfPage: {
    "@type": "ImageObject",
    url: `${MEETING_URL}/opengraph-image`,
    width: 1200,
    height: 630,
  },
  inLanguage: "en",
} as const;

export const meetingBreadcrumbJsonLd = {
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "@id": `${MEETING_URL}#breadcrumb`,
  itemListElement: [
    { "@type": "ListItem", position: 1, name: "Home", item: `${SITE_URL}/` },
    { "@type": "ListItem", position: 2, name: "Meeting recording", item: MEETING_URL },
  ],
} as const;

/* ---------- Mac voice-to-text guide ---------- */

export const GUIDE_PUBLISHED = "2026-07-11";

export const guideArticleJsonLd = {
  "@context": "https://schema.org",
  "@type": "Article",
  "@id": `${GUIDE_URL}#article`,
  headline: "How to use voice to text on Mac — in any app, offline",
  description:
    "A practical guide to setting up voice typing on a Mac, choosing a shortcut and local model, reviewing transcripts, and dictating into any app.",
  url: GUIDE_URL,
  mainEntityOfPage: { "@id": `${GUIDE_URL}#webpage` },
  image: {
    "@type": "ImageObject",
    url: `${GUIDE_URL}/opengraph-image`,
    width: 1200,
    height: 630,
  },
  datePublished: GUIDE_PUBLISHED,
  dateModified: GUIDE_PUBLISHED,
  author: { "@id": PERSON_ID },
  publisher: { "@id": PERSON_ID },
  about: { "@id": SOFTWARE_ID },
  articleSection: "Mac dictation",
  inLanguage: "en",
} as const;

export const guidePageJsonLd = {
  "@context": "https://schema.org",
  "@type": "WebPage",
  "@id": `${GUIDE_URL}#webpage`,
  url: GUIDE_URL,
  name: "How to use voice to text on Mac",
  description:
    "Set up voice to text on a Mac in minutes and dictate into any app with a global hotkey.",
  isPartOf: { "@id": WEBSITE_ID },
  mainEntity: { "@id": `${GUIDE_URL}#article` },
  about: { "@id": SOFTWARE_ID },
  breadcrumb: { "@id": `${GUIDE_URL}#breadcrumb` },
  inLanguage: "en",
} as const;

export const guideBreadcrumbJsonLd = {
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "@id": `${GUIDE_URL}#breadcrumb`,
  itemListElement: [
    { "@type": "ListItem", position: 1, name: "Home", item: `${SITE_URL}/` },
    { "@type": "ListItem", position: 2, name: "Mac voice-to-text guide", item: GUIDE_URL },
  ],
} as const;

export const themeInitScript = `(function () {
  try {
    var t = localStorage.getItem('vtt-theme');
    if (t === 'light' || t === 'dark') {
      document.documentElement.setAttribute('data-theme', t);
    }
  } catch (e) {}
})();`;
