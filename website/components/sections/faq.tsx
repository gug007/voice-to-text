import type { ReactNode } from "react";
import Link from "next/link";

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
    question: "Can I review or edit the transcript before it types?",
    answer: (
      <>
        Yes — that&rsquo;s the default. After you stop speaking, the transcript appears in a small floating
        panel where you can edit it, run one-click AI actions on it, resume dictating at the caret (⌘R),
        paste it (Return), or discard it (Esc). Nothing types until you confirm. If you&rsquo;d rather have
        text pasted immediately, switch off <em>Review before pasting</em> in Settings.
      </>
    ),
  },
  {
    question: "Can it clean up, translate, or summarize what I said?",
    answer: (
      <>
        Yes. AI Actions appear as one-click buttons in the review panel (with ⌘1–⌘9 shortcuts):{" "}
        <em>Clean transcript</em>, <em>To English</em>, <em>Improve prompt</em>, <em>Fix grammar</em>,{" "}
        <em>Summarize</em>, and <em>Essentials only</em> are built in, and you can write your own custom
        actions. Actions run with your own OpenAI API key and every transform can be undone before you
        paste. <a className="link" href="#review">See how it works.</a>
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
      "The current builds require macOS 26.4 or later and an Apple Silicon Mac (M1 or newer). Intel Macs are not supported because the local models rely on the Apple Neural Engine. Cloud models work on any supported Mac with an internet connection.",
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
    question: "Does it transcribe in real time?",
    answer: (
      <>
        Yes, with a streaming cloud model. Pick <strong>Scribe v2 Realtime</strong> (ElevenLabs) or{" "}
        <strong>GPT-4o Transcribe Realtime</strong> (OpenAI) and your words appear live in the recording HUD
        as you speak, then paste when you finish. If the streaming connection can&rsquo;t be opened, the app
        automatically falls back to transcribing the finished recording. Local models transcribe when you
        stop. <a className="link" href="#realtime">Watch the live demo.</a>
      </>
    ),
  },
  {
    question: "How is VoiceToText different from Apple Dictation, Apple Intelligence, or Wispr Flow?",
    answer: (
      <>
        <strong>Apple Dictation</strong> is tied to Apple&rsquo;s servers for full quality.{" "}
        <strong>Apple Intelligence</strong> writing tools rewrite text after the fact — they are not
        dictation at the cursor. <strong>Wispr Flow</strong> is a paid subscription that always sends audio
        to the cloud. VoiceToText is free, open source, on-device by default, works as press-to-toggle or
        hold-to-talk, and lets you bring your own OpenAI or ElevenLabs key when you want maximum accuracy or
        live streaming. <a className="link" href="#compare">See the full comparison.</a>
      </>
    ),
  },
  {
    question: "What languages are supported?",
    answer: (
      <>
        Whisper models support 99 languages out of the box. Parakeet TDT v3 covers 25 European languages
        plus Japanese and is the fastest local option. ElevenLabs Scribe v2 Realtime covers 90+ languages.
        The language is detected automatically — if you dictate in a language Parakeet doesn&rsquo;t cover,
        select a Whisper model in <em>Settings → Models</em>.
      </>
    ),
  },
  {
    question: "What apps does VoiceToText work in?",
    answer:
      "Any Mac app with a text field. Apple Notes, Notion, Obsidian, Bear, Pages, Google Docs, Microsoft Word, Slack, Messages, Mail, Gmail, Outlook, WhatsApp, Discord, Safari and Chrome address bars, ChatGPT, Claude.ai — if macOS puts a cursor there, your voice types into it. No app-specific setup.",
  },
  {
    question: "Can I dictate into Claude Code, Cursor, or other AI coding tools?",
    answer: (
      <>
        Yes. VoiceToText types into whatever app has focus — Claude Code, Codex CLI, Cursor, Copilot Chat,
        ChatGPT, any terminal, any editor. Press the hotkey, speak your prompt, press again. The built-in{" "}
        <em>Improve prompt</em> action can even restructure your spoken request into a clear AI prompt
        before you paste it. Developers can also trigger dictation from their own apps via the{" "}
        <code className="code-inline">voicetotext://</code> URL scheme.
      </>
    ),
  },
  {
    question: "Can VoiceToText record and transcribe meetings?",
    answer: (
      <>
        Yes. Alongside hotkey dictation, VoiceToText can record a full meeting or conversation — capturing
        your microphone and your Mac&rsquo;s system audio (the other participants in Zoom, Google Meet,
        Microsoft Teams, FaceTime, and any other app) in the background while you keep working. When you
        stop, it transcribes the recording with your chosen model — on-device by default — and saves the
        audio and transcript to your history. Recording system audio uses Apple&rsquo;s ScreenCaptureKit and
        requires Screen Recording permission (audio only — it never records the screen).{" "}
        <Link className="link" href="/meeting-recording">See how meeting recording works.</Link>
      </>
    ),
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

export function Faq() {
  return (
    <section className="section faq reveal" id="faq" aria-labelledby="faq-title">
      <div className="container">
        <p className="section__eyebrow">FAQ</p>
        <h2 id="faq-title" className="section__title">
          Voice to text on Mac — frequently asked questions.
        </h2>
        <p className="section__deck">
          Answers to what developers, writers, and privacy-conscious users ask before installing this speech
          to text Mac app.
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
