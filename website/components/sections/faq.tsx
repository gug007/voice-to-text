import type { ReactNode } from "react";

import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";

type Faq = {
  question: string;
  answer: ReactNode;
};

// KEEP IN SYNC with `faqEntries` in lib/seo.ts (the FAQPage JSON-LD source).
// Google requires the structured data to match the visible answers — edit both.

const FAQS: Faq[] = [
  {
    question: "Is VoiceToText free?",
    answer: (
      <>
        Yes — completely free, forever. VoiceToText is free and open source, with the full source code on
        GitHub. No paid tiers, no accounts, and no in-app purchases.{" "}
        <a className="link" href="#download">Download it free.</a>
      </>
    ),
  },
  {
    question: "Does it work offline? Is my voice data sent anywhere?",
    answer:
      "Yes, transcription works fully offline by default. Local models (Whisper, Parakeet) run on the Apple Neural Engine — your audio never leaves your Mac. The app's only network traffic is one-time model downloads and a daily update check against GitHub Releases. Cloud models are strictly opt-in: audio is sent directly to the provider (OpenAI or ElevenLabs) under your own API key only when you explicitly select a cloud engine, and AI transcript actions use your OpenAI key the same way. VoiceToText itself never receives your audio.",
  },
  {
    question: "How do I use voice to text on my Mac?",
    answer: (
      <>
        Install from the DMG, grant Microphone and Accessibility permissions, then press <HotkeyCombo /> in
        any app, speak, and press it again. The transcript pops up for a quick review — hit Return and
        it&rsquo;s pasted at the cursor. Prefer zero friction? Turn review off in Settings and text lands
        instantly. Prefer hold-to-talk? Switch the shortcut to hold-to-record. Works identically on MacBook
        Air, MacBook Pro, iMac, Mac mini, and Mac Studio.
      </>
    ),
  },
  {
    question: "Why does it need Accessibility permission?",
    answer:
      "Accessibility permission is how macOS lets one app type into another. VoiceToText uses it to paste transcribed text at the cursor, register the global shortcut, and catch Esc so you can cancel a recording — it does not log your keystrokes, read your screen, or access any other app’s data. (Only the optional Right Control shortcut needs the separate Input Monitoring permission.) The source code is public if you want to verify exactly how the permissions are used.",
  },
  {
    question: "What are the system requirements?",
    answer:
      "The current builds require macOS 15.0 or later and an Apple Silicon Mac (M1 or newer). Intel Macs are not supported because the local models rely on the Apple Neural Engine. Cloud models work on any supported Mac with an internet connection.",
  },
  {
    question: "How accurate is it? Which models does it use?",
    answer: (
      <>
        You choose from six local models: Parakeet TDT v3 is the fastest on-device option, Whisper Large v3
        is the most accurate offline option, and Whisper Large v3 Turbo is the best balance — plus Small,
        Base, and Tiny for older or space-constrained Macs. For the highest accuracy across accents and
        technical jargon, bring your own API key and switch to GPT-4o Transcribe, GPT-4o Mini Transcribe, or
        Whisper-1 (OpenAI), or Scribe v2 Realtime (ElevenLabs) in <em>Settings → Models</em>.
      </>
    ),
  },
  {
    question: "What apps does VoiceToText work in?",
    answer:
      "Any Mac app with a text field. Apple Notes, Notion, Obsidian, Bear, Pages, Google Docs, Microsoft Word, Slack, Messages, Mail, Gmail, Outlook, WhatsApp, Discord, Safari and Chrome address bars, ChatGPT, Claude.ai — if macOS puts a cursor there, your voice types into it. No app-specific setup.",
  },
  {
    question: "Do you collect any usage data or telemetry?",
    answer:
      "The app collects nothing: no accounts, no analytics, no first-party servers. With a local model your audio generates zero network traffic — the only connections the app makes are model downloads and an update check against GitHub Releases. If you opt in to a cloud model, audio goes directly from your Mac to the provider — VoiceToText is never in that path. The repo is public; verify it yourself or watch traffic with Little Snitch. (This website uses Google Analytics to count visits; the app itself contains no analytics code.)",
  },
];

export function Faq() {
  return (
    <section className="section faq reveal" id="faq" aria-labelledby="faq-title">
      <div className="container">
        <p className="section__eyebrow">FAQ</p>
        <h2 id="faq-title" className="section__title">
          What you need to know before installing.
        </h2>
        <p className="section__deck">
          Eight direct answers about privacy, setup, compatibility, and everyday use.
        </p>
        <div className="faq__list">
          {FAQS.map(({ question, answer }) => (
            <details key={question} className="faq-item">
              <summary className="faq-item__q">
                <span>{question}</span>
                <Icon name="chevron-down" className="faq-item__chevron" />
              </summary>
              <div className="faq-item__a">{answer}</div>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
