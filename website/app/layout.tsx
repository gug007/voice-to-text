import type { Metadata, Viewport } from "next";
import Script from "next/script";
import "./globals.css";

const SITE_URL = "https://voicetotext.cc";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Voice to Text for Mac — Free Speech to Text App · VoiceToText",
  description:
    "Free voice to text app for Mac. Hold a hotkey, speak, release — words type into any app instantly. Offline on Apple Silicon, no account. Download free.",
  keywords: [
    "voice to text mac",
    "speech to text mac",
    "voice to text macbook",
    "how to use voice to text on mac",
    "voice to text app for mac",
    "speak to text app for mac",
    "free speech to text mac",
    "mac dictation",
    "offline speech recognition mac",
    "push to talk dictation",
  ],
  authors: [{ name: "Gurgen Abagyan", url: "https://github.com/gug007" }],
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
    },
  },
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    siteName: "VoiceToText",
    url: SITE_URL,
    title: "Voice to Text for Mac — Free Speech to Text App · VoiceToText",
    description:
      "Free voice to text and speech to text app for Mac. Hold a hotkey, speak, release — words type into any app. Offline on Apple Silicon, no account, open source.",
    images: [
      {
        url: "/og-image.png",
        width: 1200,
        height: 630,
        alt: "VoiceToText — free voice to text and speech to text app for Mac, typing into a code editor",
      },
    ],
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: "Voice to Text for Mac — Free Speech to Text · VoiceToText",
    description:
      "Free voice to text & speech to text for Mac. Push-to-talk, offline on the Apple Neural Engine. Open-source alternative to Wispr Flow and Superwhisper.",
    images: ["/og-image.png"],
  },
  icons: {
    icon: [
      { url: "/icon-64.png", sizes: "64x64", type: "image/png" },
      { url: "/app-icon.png", sizes: "512x512", type: "image/png" },
    ],
    apple: { url: "/app-icon.png", sizes: "512x512", type: "image/png" },
  },
  formatDetection: { telephone: false },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#0A0A0B" },
    { media: "(prefers-color-scheme: light)", color: "#FFFFFF" },
  ],
  colorScheme: "dark light",
};

const themeInitScript = `
(function () {
  try {
    var t = localStorage.getItem('vtt-theme');
    if (t === 'light' || t === 'dark') {
      document.documentElement.setAttribute('data-theme', t);
    }
  } catch (e) {}
})();
`;

const softwareApplicationJsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "VoiceToText — Voice to Text for Mac",
  alternateName: ["Voice to Text Mac", "Speech to Text Mac", "VoiceToText"],
  description:
    "Free, open-source voice to text and speech to text app for Mac. Push-to-talk dictation that runs offline on the Apple Neural Engine, with optional OpenAI cloud models, and types into any focused macOS app.",
  keywords:
    "voice to text mac, speech to text mac, mac dictation, push-to-talk dictation, offline speech recognition mac, free voice to text",
  url: SITE_URL + "/",
  downloadUrl: "https://github.com/gug007/voice-to-text/releases/latest/download/VoiceToText.dmg",
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
  license: "https://github.com/gug007/voice-to-text/blob/main/LICENSE",
  isAccessibleForFree: true,
  author: {
    "@type": "Person",
    name: "Gurgen Abagyan",
    url: "https://github.com/gug007",
    sameAs: "https://github.com/gug007",
  },
  image: SITE_URL + "/og-image.png",
  featureList: [
    "Voice to text on Mac with a push-to-talk global hotkey (Option+Space, customizable)",
    "Speech to text that runs offline on-device (no internet required)",
    "Apple Neural Engine acceleration",
    "WhisperKit and FluidAudio (Parakeet) speech recognition engines",
    "Optional OpenAI cloud models (GPT-4o Transcribe, GPT-4o Mini Transcribe, Whisper-1)",
    "Types transcribed text into any focused macOS app",
    "Menu bar app, native SwiftUI for Mac",
  ],
};

const faqJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: [
    {
      "@type": "Question",
      name: "Is VoiceToText free?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "Yes — completely free, forever. VoiceToText is open source (OSI-approved license) with no paid tiers, no accounts, and no in-app purchases.",
      },
    },
    {
      "@type": "Question",
      name: "Does it work offline? Is my voice data sent anywhere?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "Yes, it works fully offline by default. Local models (Whisper, Parakeet) run on the Apple Neural Engine — audio never leaves your Mac and the app makes zero network calls. Cloud models (OpenAI GPT-4o Transcribe, etc.) are strictly opt-in: audio is sent directly to OpenAI under your own API key only when you explicitly select a cloud engine. VoiceToText itself never receives your audio.",
      },
    },
    {
      "@type": "Question",
      name: "How do I use voice to text on my Mac?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "Install from the DMG, grant Microphone and Accessibility permissions, then hold Option+Space in any app, speak, and release. Text is typed at the cursor — no panel, no copy-paste. Works identically on MacBook Air, MacBook Pro, iMac, Mac mini, and Mac Studio (M1 or newer).",
      },
    },
    {
      "@type": "Question",
      name: "Why does it need Accessibility permission?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "Accessibility permission is how macOS lets one app type into another. VoiceToText uses it solely to inject transcribed text at the cursor — it does not read your screen, monitor keystrokes, or access any other app's data. The source code is public if you want to verify exactly how the permission is used.",
      },
    },
    {
      "@type": "Question",
      name: "What are the system requirements?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "macOS 14 Sonoma or later, and an Apple Silicon Mac (M1 or newer). Intel Macs are not supported because the local models rely on the Apple Neural Engine. Cloud models work on any supported Mac with an internet connection.",
      },
    },
    {
      "@type": "Question",
      name: "How accurate is it? Which models does it use?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "Local accuracy is near OpenAI Whisper quality for English; Parakeet is faster for English and Whisper-large is the best local option for 99 languages. For the highest accuracy across accents and technical jargon, bring your own OpenAI API key (stored in the macOS Keychain) and switch to GPT-4o Transcribe, GPT-4o Mini Transcribe, or Whisper-1 in Settings.",
      },
    },
    {
      "@type": "Question",
      name: "How is VoiceToText different from Apple Dictation, Apple Intelligence, or Wispr Flow?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "Apple Dictation is toggle-based and tied to Apple's servers. Apple Intelligence writing tools rewrite text after the fact — they are not real-time dictation at the cursor. Wispr Flow is a paid subscription that always sends audio to the cloud. VoiceToText is free, open source, push-to-talk, on-device by default, and lets you bring your own OpenAI key when you want maximum accuracy.",
      },
    },
    {
      "@type": "Question",
      name: "What languages are supported?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "WhisperKit supports 99 languages out of the box — the same coverage as OpenAI's Whisper model. Parakeet (FluidAudio) is English-only but faster for English speakers. If you dictate in a non-English language, select a Whisper model in Settings → Models.",
      },
    },
    {
      "@type": "Question",
      name: "What apps does VoiceToText work in?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "Any Mac app with a text field. Apple Notes, Notion, Obsidian, Bear, Pages, Google Docs, Microsoft Word, Slack, Messages, Mail, Gmail, Outlook, WhatsApp, Discord, Safari and Chrome address bars, ChatGPT, Claude.ai — if macOS puts a cursor there, your voice types into it. No app-specific setup.",
      },
    },
    {
      "@type": "Question",
      name: "Can I dictate into Claude Code, Cursor, or other AI coding tools?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "Yes. VoiceToText types into whatever app has focus — Claude Code, Codex CLI, Cursor, Copilot Chat, ChatGPT, any terminal, any editor. Hold the hotkey, speak your prompt, release. No switching windows, no copy-paste.",
      },
    },
    {
      "@type": "Question",
      name: "Do you collect any usage data or telemetry?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "No. No accounts, no analytics, no first-party servers. The app makes zero network calls with a local model. If you opt in to a cloud model, audio goes directly from your Mac to OpenAI — VoiceToText is never in that path. The repo is public; verify it yourself or watch traffic with Little Snitch.",
      },
    },
  ],
};

const personJsonLd = {
  "@context": "https://schema.org",
  "@type": "Person",
  name: "Gurgen Abagyan",
  url: "https://github.com/gug007",
  sameAs: ["https://github.com/gug007"],
};

const GA_ID = "G-6XX9WSS0TH";

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <head>
        <link rel="dns-prefetch" href="https://github.com" />
        <script
          dangerouslySetInnerHTML={{ __html: themeInitScript.trim() }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(softwareApplicationJsonLd) }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(faqJsonLd) }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(personJsonLd) }}
        />
      </head>
      <body>
        <Script
          src={`https://www.googletagmanager.com/gtag/js?id=${GA_ID}`}
          strategy="afterInteractive"
        />
        <Script id="ga-init" strategy="afterInteractive">{`
          window.dataLayer = window.dataLayer || [];
          function gtag(){dataLayer.push(arguments);}
          gtag('js', new Date());
          gtag('config', '${GA_ID}');
        `}</Script>

        {/* Icon sprite — referenced via <use href="#i-NAME"> throughout the page */}
        <svg
          aria-hidden="true"
          width="0"
          height="0"
          style={{ position: "absolute" }}
          focusable="false"
        >
          <defs>
            <symbol id="i-download" viewBox="0 0 16 16">
              <path d="M8 1v9m0 0l-3-3m3 3l3-3M2 13h12" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </symbol>
            <symbol id="i-github" viewBox="0 0 16 16">
              <path fill="currentColor" d="M8 .2a8 8 0 00-2.53 15.59c.4.07.55-.17.55-.38v-1.34c-2.22.48-2.7-1.07-2.7-1.07-.36-.92-.89-1.17-.89-1.17-.73-.5.06-.49.06-.49.8.06 1.23.83 1.23.83.72 1.23 1.88.87 2.34.67.07-.52.28-.88.51-1.08-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.58.82-2.14-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.65 7.65 0 014 0c1.53-1.03 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.14 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48v2.2c0 .21.15.46.55.38A8 8 0 008 .2" />
            </symbol>
            <symbol id="i-chevron-down" viewBox="0 0 16 16">
              <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </symbol>
            <symbol id="i-lock" viewBox="0 0 20 20">
              <rect x="4" y="9" width="12" height="9" rx="2" stroke="currentColor" strokeWidth="1.75" fill="none" />
              <path d="M7 9V6a3 3 0 016 0v3" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" />
            </symbol>
            <symbol id="i-bolt" viewBox="0 0 20 20">
              <path d="M11 2L4 11h5l-1 7 7-9h-5l1-7z" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </symbol>
            <symbol id="i-box" viewBox="0 0 20 20">
              <path d="M10 2L3 6v8l7 4 7-4V6l-7-4zM3 6l7 4 7-4M10 10v8" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </symbol>
            <symbol id="i-mic" viewBox="0 0 20 20">
              <rect x="7" y="2" width="6" height="11" rx="3" stroke="currentColor" strokeWidth="1.75" fill="none" />
              <path d="M4 10a6 6 0 0012 0M10 16v3" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" />
            </symbol>
            <symbol id="i-keyboard" viewBox="0 0 20 20">
              <rect x="2" y="5" width="16" height="10" rx="2" stroke="currentColor" strokeWidth="1.75" fill="none" />
              <path d="M5 9h.01M8 9h.01M11 9h.01M14 9h.01M6 12h8" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
            </symbol>
            <symbol id="i-sparkle" viewBox="0 0 20 20">
              <path d="M10 2v5M10 13v5M2 10h5M13 10h5M5 5l3 3M12 12l3 3M15 5l-3 3M8 12l-3 3" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" />
            </symbol>
            <symbol id="i-agent" viewBox="0 0 20 20">
              <rect x="3" y="4" width="14" height="10" rx="2" stroke="currentColor" strokeWidth="1.75" fill="none" />
              <path d="M7 8h.01M13 8h.01M7 11h6M10 14v3M7 17h6" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
            </symbol>
            <symbol id="i-apps" viewBox="0 0 20 20">
              <rect x="2" y="2" width="6" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.75" fill="none" />
              <rect x="12" y="2" width="6" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.75" fill="none" />
              <rect x="2" y="12" width="6" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.75" fill="none" />
              <rect x="12" y="12" width="6" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.75" fill="none" />
            </symbol>
            <symbol id="i-arrow-right" viewBox="0 0 16 16">
              <path d="M3 8h10M9 4l4 4-4 4" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </symbol>
            <symbol id="i-cloud" viewBox="0 0 20 20">
              <path d="M14.5 15H6a4 4 0 01-.4-7.98A5 5 0 0115.5 8a3.5 3.5 0 01-1 7z" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </symbol>
          </defs>
        </svg>

        <a className="skip-link" href="#main">Skip to main content</a>
        {children}
      </body>
    </html>
  );
}
