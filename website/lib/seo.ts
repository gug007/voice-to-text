import {
  APP_REQUIREMENTS,
  BUILT_IN_ACTIONS,
  MODEL_CATALOG,
  cloudModels,
  defaultModel,
  liveTextModelNames,
  localModels,
} from "./app-facts";
import {
  AUTHOR_URL,
  DMG_URL,
  GUIDE_URL,
  REPO_URL,
  SITE_URL,
} from "./constants";
import { page } from "./pages";
import {
  HOME_PAGE_ID,
  PERSON_ID,
  SOFTWARE_ID,
  VIDEO_ID,
  WEBSITE_ID,
  type FaqEntry,
} from "./seo-ids";

// lib/seo.ts is the home page's structured data. The shared @ids and the other
// pages' JSON-LD live in their own modules and are re-exported here, so
// existing `@/lib/seo` imports keep working.
export * from "./seo-ids";
export * from "./seo-meeting";
export * from "./seo-guide";

export const HOME_TITLE = "Free Voice-to-Text App for Mac — Offline & No Account";
export const HOME_DESCRIPTION =
  "Free voice to text for Mac. Press Option+Space to dictate into any app, or record meetings and transcribe them. Works offline by default, no account.";
export const HOME_TWITTER_DESCRIPTION =
  "Dictate into any Mac app with Option+Space, or record calls and get a transcript. Free, works offline by default, no account, source on GitHub.";

const NUMBER_WORDS = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"];

/** "Six", "Nine" — a sentence should not open on a digit. */
export function countWord(n: number): string {
  return NUMBER_WORDS[n] ?? String(n);
}

const LOCAL = localModels();
const CLOUD = cloudModels();
const DEFAULT_MODEL = defaultModel();
const joinList = (xs: readonly string[]) =>
  new Intl.ListFormat("en", { style: "long", type: "conjunction" }).format(xs);
const lower = (n: number) => countWord(n).toLowerCase();
const CLOUD_BY_PROVIDER = [...new Set(CLOUD.map((m) => m.provider))].map(
  (p) => `${p} ${joinList(CLOUD.filter((m) => m.provider === p).map((m) => m.name))}`,
);
// GPT Realtime Whisper is live but only shows its text when you stop.
const LIVE_WORDS = liveTextModelNames("word by word");
const LIVE_PHRASES = liveTextModelNames("phrase by phrase");

// This describes the product entity. Do not add aggregateRating/review until
// a genuine review is visible on the page and can be represented faithfully.
export const softwareApplicationJsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "@id": SOFTWARE_ID,
  name: "VoiceToText",
  alternateName: "VoiceToText for Mac",
  description: `Free voice to text and speech to text app for Mac, with source available on GitHub. Press Option+Space in any app, speak, check the text, and it is pasted at your cursor. Record meetings and calls (microphone plus system audio) or import an audio or video file, and keep every transcript in a searchable local history. Transcription runs on your Mac with ${lower(LOCAL.length)} local models after a one-time download, or with ${lower(CLOUD.length)} optional OpenAI and ElevenLabs cloud models under your own API key. Optional AI actions, summaries, and action items use your own OpenAI key.`,
  keywords:
    "voice to text mac, speech to text mac, mac dictation, dictation app for mac, offline speech recognition mac, free voice to text, meeting transcription mac, whisper mac app",
  url: `${SITE_URL}/`,
  sameAs: REPO_URL,
  downloadUrl: DMG_URL,
  installUrl: DMG_URL,
  softwareHelp: { "@id": `${GUIDE_URL}#webpage` },
  applicationCategory: "UtilitiesApplication",
  applicationSubCategory: "Speech to Text",
  operatingSystem: APP_REQUIREMENTS.os,
  processorRequirements: APP_REQUIREMENTS.processor,
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
    "Dictate into any Mac app with a global shortcut (Option+Space by default): press to toggle or hold to record, and rebind it to any key with a modifier, a lone F1–F20 key, or Right Control on its own",
    "Recording HUD with a live level meter and a timer; Esc cancels",
    "Review before pasting, on by default: edit the transcript, then press Return or the shortcut again to paste, or turn review off to paste right away",
    "Resume with Command-R to record another take at the caret",
    "Text is pasted at the cursor with a standard Command-V, and your previous clipboard is put back",
    "Speech to text on your Mac after a one-time model download; with a local model, audio never leaves the Mac, and the default Parakeet model works with the network off",
    `${MODEL_CATALOG.length} transcription models: ${lower(LOCAL.length)} local and ${lower(CLOUD.length)} optional cloud models`,
    `${countWord(LOCAL.length)} local models: ${DEFAULT_MODEL.name} (the default, ${DEFAULT_MODEL.languagesInApp}) and ${joinList(LOCAL.filter((m) => !m.isDefault).map((m) => m.name))}`,
    `${countWord(CLOUD.length)} optional cloud models with your own API key: ${CLOUD_BY_PROVIDER.join("; ")}`,
    `Live text while you speak with streaming cloud models: word by word with ${joinList(LIVE_WORDS)}, phrase by phrase with ${joinList(LIVE_PHRASES)}`,
    "Models pane with a 1–10 quality score based on published word error rates, and the per-hour list price of each cloud model",
    `Optional AI actions in the review panel, off by default: ${BUILT_IN_ACTIONS.join(", ")}, and your own custom actions, run with Command-1 to Command-9 on your own OpenAI key`,
    "Record conversations and meetings from any app: your microphone plus system audio via ScreenCaptureKit, with no bot joining the call; start from the app, the menu bar, or an optional conversation shortcut",
    "Transcribe an audio or video file (MP3, M4A, WAV, AIFF, MP4, MOV, and other formats macOS can read) — on-device by default",
    "Speaker labels (Speaker 1, Speaker 2, …) from the optional cloud model GPT-4o Transcribe Diarize on your own OpenAI key, with names you can assign to each speaker",
    "AI summaries, action-item checklists, and custom-prompt results for any recording, using your own OpenAI key",
    "Local history of up to 200 recordings, with search across transcripts, summaries, action items, and speaker names, plus favorites, playback, copy, and undoable deletes",
    "Regenerate any transcript with a different model and keep every version side by side",
    "Conversation recordings interrupted by a crash or power loss are recovered into History on next launch",
    "Menu bar item with dictation and conversation controls, and an optional menu-bar-only mode",
    "Automate dictation from Raycast, Shortcuts, or scripts with the voicetotext:// URL scheme (toggle, start, stop, cancel)",
    "Checks GitHub Releases for updates and installs them when you confirm",
    "Native SwiftUI app — no Electron",
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
  name: HOME_TITLE,
  description: HOME_DESCRIPTION,
  datePublished: page("/").published,
  dateModified: page("/").modified,
  isPartOf: { "@id": WEBSITE_ID },
  mainEntity: { "@id": SOFTWARE_ID },
  primaryImageOfPage: {
    "@type": "ImageObject",
    url: `${SITE_URL}/opengraph-image`,
    width: 1200,
    height: 630,
  },
  video: { "@id": VIDEO_ID },
  inLanguage: "en",
} as const;

export const videoObjectJsonLd = {
  "@context": "https://schema.org",
  "@type": "VideoObject",
  "@id": VIDEO_ID,
  name: "VoiceToText for Mac — dictating into a coding workspace",
  description:
    "A silent 20-second screen recording showing VoiceToText turning a spoken coding request into text directly inside a Mac coding workspace.",
  thumbnailUrl: `${SITE_URL}/product-demo-poster.png`,
  uploadDate: "2026-07-17T00:00:00+04:00",
  duration: "PT19S",
  contentUrl: `${SITE_URL}/product-demo.mp4`,
  url: `${SITE_URL}/#demo`,
  inLanguage: "en",
  isFamilyFriendly: true,
  about: { "@id": SOFTWARE_ID },
  creator: { "@id": PERSON_ID },
  mainEntityOfPage: { "@id": HOME_PAGE_ID },
} as const;

// The home FAQ's single source: components/sections/faq.tsx renders these
// entries as-is and faqPageJsonLd below serialises the same array, so the
// visible answers and the FAQPage JSON-LD cannot drift apart.
export const faqEntries: FaqEntry[] = [
  {
    question: "Is VoiceToText free?",
    answer:
      "Yes. VoiceToText has no paid tier, no account, and no in-app purchases, and its source is available on GitHub. The optional cloud models and AI features bill your own OpenAI or ElevenLabs account at the provider's prices.",
  },
  {
    question: "Does it work offline? Is my voice data sent anywhere?",
    answer:
      "Yes, with Parakeet, the default model: after a one-time download it works with the network off. With any local model, Parakeet or Whisper, your audio is transcribed on your Mac and never leaves it. The current version does contact Hugging Face each time it loads a Whisper model, so for a fully offline Mac, use Parakeet. Apart from model downloads and an update check, nothing leaves your Mac unless you opt in: a cloud model sends audio directly to OpenAI or ElevenLabs under your own API key, and AI actions, summaries, and action items send the transcript text to OpenAI. VoiceToText has no servers of its own, so it never receives your audio or your text.",
  },
  {
    question: "How do I use voice to text on my Mac?",
    answer:
      "Install from the DMG and allow Microphone and Accessibility. Then press Option+Space in any app, speak, and press it again. The transcript opens in a small review panel: press Return, or the shortcut again, to paste it at your cursor, or Esc to discard it. You can turn review off to paste right away, or switch the shortcut to hold-to-record. It works the same on any Apple Silicon MacBook Air, MacBook Pro, iMac, Mac mini, or Mac Studio.",
  },
  {
    question: "What apps does VoiceToText work in?",
    answer:
      "Any app where Command-V pastes text: Notes, Notion, Obsidian, Google Docs, Word, Slack, Messages, Mail, Gmail, Outlook, WhatsApp, Discord, browser address bars, ChatGPT, Claude, Cursor, and Terminal. VoiceToText puts the transcript on the clipboard, sends a standard Command-V, and then puts your previous clipboard back, so there is no per-app setup. A field that blocks pasting won't receive the text.",
  },
  {
    question: "Why does it need Accessibility permission?",
    answer:
      "macOS asks for Accessibility whenever one app sends keystrokes to another. VoiceToText uses it to paste with Command-V, to run the global shortcut, and to catch Esc so you can cancel, so recording won't start without it. It does not log your typing, read your screen, or read other apps' content. A Right Control shortcut also needs Input Monitoring, and recording calls needs Screen Recording to capture the other participants' audio (audio only, never the screen).",
  },
  {
    question: "What are the system requirements?",
    answer:
      "macOS 15.0 or later on an Apple Silicon Mac (M1 or newer). Current builds are Apple Silicon only, so Intel Macs are not supported. The default local model is a one-time download of about 470 MB; cloud models need an internet connection and your own API key.",
  },
  {
    question: "How accurate is it? Which models does it use?",
    answer:
      "You choose from 15 models. Parakeet TDT v3 is the recommended default: fast, on-device, and 25 European languages. Whisper Large v3 is the most accurate local model; Large v3 Turbo, Small, Base, and Tiny trade accuracy for size. With your own API key, GPT Transcribe tops the cloud list, followed by Scribe v2 Realtime, and GPT-4o Mini Transcribe is the cheapest at $0.18 per hour. The Models pane shows a 1–10 quality score for each, based on published word error rates rather than our own tests, so try two or three on your own voice.",
  },
  {
    question: "Which languages does it support?",
    answer:
      "It depends on the model, and there is no language setting to change. Parakeet TDT v3, the default, recognizes 25 European languages automatically. The local Whisper models transcribe English in VoiceToText. For any other language, use a cloud model with your own key: OpenAI's models cover 99 or more languages and ElevenLabs Scribe v2 Realtime more than 90, detected automatically.",
  },
  {
    question: "Can it record meetings and write summaries or action items?",
    answer:
      "Yes. Conversations records your microphone and the call's system audio from any app, such as Zoom, Meet, Teams, or FaceTime, with no bot joining, and transcribes it when you stop, on your Mac by default. You can also drop in an audio or video file. With your own OpenAI key, any recording can get a summary, an action-item checklist, or the result of your own prompt; that sends the transcript text to OpenAI. Speaker labels need the cloud model GPT-4o Transcribe Diarize.",
  },
  {
    question: "Do you collect any usage data or telemetry?",
    answer:
      "No. The app has no analytics, no accounts, and no servers of its own. Without API keys, its only connections are to Hugging Face, for model downloads and each time a Whisper model loads, and an update check against GitHub Releases at launch and once a day. Adding a key sends a one-time verification request to that provider; after that, a cloud model sends audio, and AI actions or summaries send transcript text, directly from your Mac to the provider. The source is on GitHub if you want to check, or watch the traffic with a tool like Little Snitch. This website uses Google Analytics to count visits; the app contains no analytics code.",
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

export const themeInitScript = `(function () {
  try {
    var t = localStorage.getItem('vtt-theme');
    if (t === 'light' || t === 'dark') {
      document.documentElement.setAttribute('data-theme', t);
    }
  } catch (e) {}
})();`;
