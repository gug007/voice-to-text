import { AUTHOR_URL, DMG_URL, LICENSE_URL, SITE_URL } from "./constants";

export const softwareApplicationJsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "VoiceToText — Voice to Text for Mac",
  alternateName: ["Voice to Text Mac", "Speech to Text Mac", "VoiceToText"],
  description:
    "Free, open-source voice to text and speech to text app for Mac. Push-to-talk dictation that runs offline on the Apple Neural Engine, with optional OpenAI cloud models, and types into any focused macOS app.",
  keywords:
    "voice to text mac, speech to text mac, mac dictation, push-to-talk dictation, offline speech recognition mac, free voice to text",
  url: `${SITE_URL}/`,
  downloadUrl: DMG_URL,
  applicationCategory: "ProductivityApplication",
  applicationSubCategory: "Speech to Text",
  operatingSystem: "macOS 14.0",
  processorRequirements: "Apple Silicon (M1 or newer)",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
    availability: "https://schema.org/InStock",
  },
  license: LICENSE_URL,
  isAccessibleForFree: true,
  author: {
    "@type": "Person",
    name: "Gurgen Abagyan",
    url: AUTHOR_URL,
    sameAs: AUTHOR_URL,
  },
  image: `${SITE_URL}/og-image.png`,
  featureList: [
    "Voice to text on Mac with a push-to-talk global hotkey (Option+Space, customizable)",
    "Speech to text that runs offline on-device (no internet required)",
    "Apple Neural Engine acceleration",
    "WhisperKit and FluidAudio (Parakeet) speech recognition engines",
    "Optional OpenAI cloud models (GPT-4o Transcribe, GPT-4o Mini Transcribe, Whisper-1)",
    "Types transcribed text into any focused macOS app",
    "Menu bar app, native SwiftUI for Mac",
  ],
} as const;

type FaqEntry = { question: string; answer: string };

const faqEntries: FaqEntry[] = [
  {
    question: "Is VoiceToText free?",
    answer:
      "Yes — completely free, forever. VoiceToText is open source (OSI-approved license) with no paid tiers, no accounts, and no in-app purchases.",
  },
  {
    question: "Does it work offline? Is my voice data sent anywhere?",
    answer:
      "Yes, it works fully offline by default. Local models (Whisper, Parakeet) run on the Apple Neural Engine — audio never leaves your Mac and the app makes zero network calls. Cloud models (OpenAI GPT-4o Transcribe, etc.) are strictly opt-in: audio is sent directly to OpenAI under your own API key only when you explicitly select a cloud engine. VoiceToText itself never receives your audio.",
  },
  {
    question: "How do I use voice to text on my Mac?",
    answer:
      "Install from the DMG, grant Microphone and Accessibility permissions, then hold Option+Space in any app, speak, and release. Text is typed at the cursor — no panel, no copy-paste. Works identically on MacBook Air, MacBook Pro, iMac, Mac mini, and Mac Studio (M1 or newer).",
  },
  {
    question: "Why does it need Accessibility permission?",
    answer:
      "Accessibility permission is how macOS lets one app type into another. VoiceToText uses it solely to inject transcribed text at the cursor — it does not read your screen, monitor keystrokes, or access any other app's data. The source code is public if you want to verify exactly how the permission is used.",
  },
  {
    question: "What are the system requirements?",
    answer:
      "macOS 14 Sonoma or later, and an Apple Silicon Mac (M1 or newer). Intel Macs are not supported because the local models rely on the Apple Neural Engine. Cloud models work on any supported Mac with an internet connection.",
  },
  {
    question: "How accurate is it? Which models does it use?",
    answer:
      "Local accuracy is near OpenAI Whisper quality for English; Parakeet is faster for English and Whisper-large is the best local option for 99 languages. For the highest accuracy across accents and technical jargon, bring your own OpenAI API key (stored in the macOS Keychain) and switch to GPT-4o Transcribe, GPT-4o Mini Transcribe, or Whisper-1 in Settings.",
  },
  {
    question: "How is VoiceToText different from Apple Dictation, Apple Intelligence, or Wispr Flow?",
    answer:
      "Apple Dictation is toggle-based and tied to Apple's servers. Apple Intelligence writing tools rewrite text after the fact — they are not real-time dictation at the cursor. Wispr Flow is a paid subscription that always sends audio to the cloud. VoiceToText is free, open source, push-to-talk, on-device by default, and lets you bring your own OpenAI key when you want maximum accuracy.",
  },
  {
    question: "What languages are supported?",
    answer:
      "WhisperKit supports 99 languages out of the box — the same coverage as OpenAI's Whisper model. Parakeet (FluidAudio) is English-only but faster for English speakers. If you dictate in a non-English language, select a Whisper model in Settings → Models.",
  },
  {
    question: "What apps does VoiceToText work in?",
    answer:
      "Any Mac app with a text field. Apple Notes, Notion, Obsidian, Bear, Pages, Google Docs, Microsoft Word, Slack, Messages, Mail, Gmail, Outlook, WhatsApp, Discord, Safari and Chrome address bars, ChatGPT, Claude.ai — if macOS puts a cursor there, your voice types into it. No app-specific setup.",
  },
  {
    question: "Can I dictate into Claude Code, Cursor, or other AI coding tools?",
    answer:
      "Yes. VoiceToText types into whatever app has focus — Claude Code, Codex CLI, Cursor, Copilot Chat, ChatGPT, any terminal, any editor. Hold the hotkey, speak your prompt, release. No switching windows, no copy-paste.",
  },
  {
    question: "Do you collect any usage data or telemetry?",
    answer:
      "No. No accounts, no analytics, no first-party servers. The app makes zero network calls with a local model. If you opt in to a cloud model, audio goes directly from your Mac to OpenAI — VoiceToText is never in that path. The repo is public; verify it yourself or watch traffic with Little Snitch.",
  },
];

export const faqPageJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: faqEntries.map(({ question, answer }) => ({
    "@type": "Question",
    name: question,
    acceptedAnswer: { "@type": "Answer", text: answer },
  })),
} as const;

export const personJsonLd = {
  "@context": "https://schema.org",
  "@type": "Person",
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
