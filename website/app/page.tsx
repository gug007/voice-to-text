import Image from "next/image";
import { CSSProperties } from "react";

import { DictationDemo } from "@/components/dictation-demo";
import { ScrollEffects } from "@/components/scroll-effects";
import { StickyCta } from "@/components/sticky-cta";
import { ThemeToggle } from "@/components/theme-toggle";

const DMG_URL =
  "https://github.com/gug007/voice-to-text/releases/latest/download/VoiceToText.dmg";
const REPO_URL = "https://github.com/gug007/voice-to-text";

type StatusKind = "ok" | "no" | "partial";

type CompareRow = {
  label: string;
  cells: [string, string, string, string, string];
  status: [StatusKind, StatusKind, StatusKind, StatusKind, StatusKind];
  footnotes?: Partial<Record<0 | 1 | 2 | 3 | 4, number>>;
};

const COMPARE_ROWS: CompareRow[] = [
  {
    label: "Price",
    cells: [
      "Free — no paid tiers",
      "Subscription required",
      "Subscription or one-time fee",
      "One-time purchase",
      "Free (built-in)",
    ],
    status: ["ok", "no", "no", "no", "ok"],
    footnotes: { 1: 1, 2: 2, 3: 3 },
  },
  {
    label: "Open source",
    cells: ["Yes — on GitHub", "—", "—", "—", "—"],
    status: ["ok", "no", "no", "no", "no"],
  },
  {
    label: "Runs 100% offline",
    cells: [
      "On-device",
      "Cloud only",
      "On-device",
      "On-device",
      "On-device (English & select langs)",
    ],
    status: ["ok", "no", "ok", "ok", "partial"],
  },
  {
    label: "No account required",
    cells: ["None required", "Account required", "Account required", "No account", "None required"],
    status: ["ok", "no", "no", "ok", "ok"],
  },
  {
    label: "Push-to-talk (hold key)",
    cells: ["Hold ⌥ Space", "Customizable hold", "Customizable hold", "Pro (Global mode)", "Toggle only"],
    status: ["ok", "ok", "ok", "partial", "no"],
  },
  {
    label: "Works in any text field",
    cells: ["System-wide", "System-wide", "System-wide", "Pro only", "System-wide"],
    status: ["ok", "ok", "ok", "partial", "ok"],
  },
  {
    label: "Apple Neural Engine (Apple Silicon)",
    cells: [
      "Yes — Apple Silicon",
      "N/A — cloud-side inference",
      "Yes — Apple Silicon",
      "Yes — Apple Silicon",
      "Yes — Apple Silicon",
    ],
    status: ["ok", "no", "ok", "ok", "ok"],
    footnotes: { 1: 4 },
  },
  {
    label: "Native macOS app (no Electron)",
    cells: ["SwiftUI native", "Electron-based", "SwiftUI native", "SwiftUI native", "Native"],
    status: ["ok", "no", "ok", "ok", "ok"],
  },
  {
    label: "Choice of local speech engine",
    cells: [
      "Whisper + Parakeet + optional OpenAI cloud",
      "Single proprietary cloud model",
      "Multiple Whisper model sizes",
      "Multiple Whisper sizes (Pro)",
      "Apple model only",
    ],
    status: ["ok", "no", "ok", "partial", "no"],
    footnotes: { 3: 5 },
  },
];

const COLUMNS = ["VoiceToText", "Wispr Flow", "Superwhisper", "MacWhisper", "Apple Dictation"] as const;

const FAQS: Array<{ q: string; a: React.ReactNode }> = [
  {
    q: "Is VoiceToText free?",
    a: (
      <>
        Yes &mdash; completely free, forever. VoiceToText is open source (OSI-approved license) with no paid tiers,
        no accounts, and no in-app purchases.{" "}
        <a className="link" href="#download">Download it free.</a>
      </>
    ),
  },
  {
    q: "Does it work offline? Is my voice data sent anywhere?",
    a: (
      <>
        Yes, it works fully offline by default. Local models (Whisper, Parakeet) run on the Apple Neural Engine
        &mdash; audio never leaves your Mac and the app makes zero network calls. Cloud models (OpenAI GPT-4o
        Transcribe, etc.) are strictly opt-in: audio is sent directly to OpenAI under your own API key only when
        you explicitly select a cloud engine. VoiceToText itself never receives your audio.
      </>
    ),
  },
  {
    q: "How do I use voice to text on my Mac?",
    a: (
      <>
        Install from the DMG, grant Microphone and Accessibility permissions, then hold <HotkeyCombo /> in any
        app, speak, and release. Text is typed at the cursor &mdash; no panel, no copy-paste. Works identically on
        MacBook Air, MacBook Pro, iMac, Mac mini, and Mac Studio (M1 or newer).
      </>
    ),
  },
  {
    q: "Why does it need Accessibility permission?",
    a: (
      <>
        Accessibility permission is how macOS lets one app type into another. VoiceToText uses it solely to inject
        transcribed text at the cursor &mdash; it does not read your screen, monitor keystrokes, or access any
        other app&rsquo;s data. The source code is public if you want to verify exactly how the permission is used.
      </>
    ),
  },
  {
    q: "What are the system requirements?",
    a: (
      <>
        macOS 14 Sonoma or later, and an Apple Silicon Mac (M1 or newer). Intel Macs are not supported because the
        local models rely on the Apple Neural Engine. Cloud models work on any supported Mac with an internet
        connection.
      </>
    ),
  },
  {
    q: "How accurate is it? Which models does it use?",
    a: (
      <>
        Local accuracy is near OpenAI Whisper quality for English; Parakeet is faster for English and Whisper-large
        is the best local option for 99 languages. For the highest accuracy across accents and technical jargon,
        bring your own OpenAI API key (stored in the macOS Keychain) and switch to GPT-4o Transcribe, GPT-4o Mini
        Transcribe, or Whisper-1 in Settings.
      </>
    ),
  },
  {
    q: "How is VoiceToText different from Apple Dictation, Apple Intelligence, or Wispr Flow?",
    a: (
      <>
        <strong>Apple Dictation</strong> is toggle-based and tied to Apple&rsquo;s servers.{" "}
        <strong>Apple Intelligence</strong> writing tools rewrite text after the fact &mdash; they are not
        real-time dictation at the cursor. <strong>Wispr Flow</strong> is a paid subscription that always sends
        audio to the cloud. VoiceToText is free, open source, push-to-talk, on-device by default, and lets you
        bring your own OpenAI key when you want maximum accuracy.{" "}
        <a className="link" href="#compare">See the full comparison.</a>
      </>
    ),
  },
  {
    q: "What languages are supported?",
    a: (
      <>
        WhisperKit supports 99 languages out of the box &mdash; the same coverage as OpenAI&rsquo;s Whisper model.
        Parakeet (FluidAudio) is English-only but faster for English speakers. If you dictate in a non-English
        language, select a Whisper model in <em>Settings &rarr; Models</em>.
      </>
    ),
  },
  {
    q: "What apps does VoiceToText work in?",
    a: (
      <>
        Any Mac app with a text field. Apple Notes, Notion, Obsidian, Bear, Pages, Google Docs, Microsoft Word,
        Slack, Messages, Mail, Gmail, Outlook, WhatsApp, Discord, Safari and Chrome address bars, ChatGPT,
        Claude.ai &mdash; if macOS puts a cursor there, your voice types into it. No app-specific setup.
      </>
    ),
  },
  {
    q: "Can I dictate into Claude Code, Cursor, or other AI coding tools?",
    a: (
      <>
        Yes. VoiceToText types into whatever app has focus &mdash; Claude Code, Codex CLI, Cursor, Copilot Chat,
        ChatGPT, any terminal, any editor. Hold the hotkey, speak your prompt, release. No switching windows, no
        copy-paste.
      </>
    ),
  },
  {
    q: "Do you collect any usage data or telemetry?",
    a: (
      <>
        No. No accounts, no analytics, no first-party servers. The app makes zero network calls with a local
        model. If you opt in to a cloud model, audio goes directly from your Mac to OpenAI &mdash; VoiceToText is
        never in that path. The repo is public; verify it yourself or watch traffic with Little Snitch.
      </>
    ),
  },
];

const USE_CASE_APPS = [
  "Apple Notes",
  "Slack",
  "Messages",
  "Mail",
  "Gmail",
  "Notion",
  "Obsidian",
  "Pages",
  "Google Docs",
  "Safari",
  "Chrome",
  "ChatGPT",
  "Claude.ai",
  "Cursor",
  "Claude Code",
  "VS Code",
  "Warp",
  "Terminal",
];

function WaveBars() {
  const bars = Array.from({ length: 64 }, (_, i) => i);
  return (
    <div className="dictation-wave" aria-hidden="true">
      <div className="bars">
        {bars.map((i) => (
          <i key={i} style={{ "--i": i } as CSSProperties} />
        ))}
      </div>
    </div>
  );
}

function HotkeyCombo() {
  return (
    <span className="kbd-combo">
      <span className="sr-only">Option plus Space</span>
      <kbd className="keycap keycap--inline" aria-hidden="true">⌥</kbd>
      <kbd className="keycap keycap--inline" aria-hidden="true">Space</kbd>
    </span>
  );
}

export default function Home() {
  return (
    <>
      <header className="nav" data-scrolled="false">
        <div className="nav__inner">
          <a className="nav__brand" href="#top" aria-label="VoiceToText home">
            <Image className="brand-mark" src="/app-icon.png" width={26} height={26} alt="" priority />
            <span>VoiceToText</span>
          </a>
          <ul className="nav__links" role="list">
            <li><a href="#features">Features</a></li>
            <li><a href="#cloud">Cloud</a></li>
            <li><a href="#compare">Compare</a></li>
            <li><a href="#faq">FAQ</a></li>
          </ul>
          <ThemeToggle />
          <a className="btn btn--secondary btn--sm" href={REPO_URL} target="_blank" rel="noopener">
            <svg className="icon" aria-hidden="true"><use href="#i-github" /></svg>
            <span>View source on GitHub</span>
          </a>
        </div>
      </header>

      <main id="main" tabIndex={-1}>
        <section className="section hero reveal" id="top" aria-labelledby="hero-title">
          <WaveBars />
          <div className="container hero__inner">
            <p className="hero__eyebrow">Free &middot; Open source &middot; macOS</p>
            <h1 id="hero-title" className="hero__title">
              Voice to Text for Mac. Free. Offline.
            </h1>
            <p className="hero__lead">
              Push-to-talk dictation for Mac. On-device. No account. Free.
            </p>
            <p className="hero__subcopy">
              Hold <HotkeyCombo />, speak, release &mdash; your words land at the cursor in Notes, Slack, Mail,
              Notion, ChatGPT, or any Mac app, transcribed offline on the Apple Neural Engine.
            </p>
            <div className="hero__ctas">
              <a className="btn btn--primary btn--lg" href={DMG_URL} download>
                <svg className="icon" aria-hidden="true"><use href="#i-download" /></svg>
                <span>Get it free — download for Mac</span>
              </a>
              <a className="btn btn--secondary" href={REPO_URL} target="_blank" rel="noopener">
                <svg className="icon" aria-hidden="true"><use href="#i-github" /></svg>
                <span>View source on GitHub</span>
              </a>
            </div>
            <p className="hero__meta">Free &middot; Open source &middot; No account &middot; No subscription</p>
            <p className="hero__meta-sub t-caption">
              Requires macOS 14 Sonoma+ &middot; Apple Silicon only (M1+) &middot; Intel Macs not supported.
            </p>
          </div>
        </section>

        <section className="proof reveal" id="proof" aria-labelledby="proof-title">
          <div className="container proof__inner">
            <h2 id="proof-title" className="sr-only">Open source on GitHub</h2>
            <ul className="proof__pills" role="list">
              <li className="chip chip--accent">
                <span className="chip__dot" aria-hidden="true"></span>
                100% open source
              </li>
              <li className="chip">
                <a href={REPO_URL} target="_blank" rel="noopener" className="chip__link">
                  Browse the repo on GitHub
                </a>
              </li>
              <li className="chip">Built in public</li>
            </ul>
            <p className="proof__provenance">
              Powered by OpenAI Whisper (via WhisperKit) and Parakeet (via FluidAudio), on the Apple Neural Engine.
              <a className="proof__link" href={REPO_URL} target="_blank" rel="noopener">
                Read the source code <svg className="icon icon--sm" aria-hidden="true"><use href="#i-arrow-right" /></svg>
              </a>
            </p>
          </div>
        </section>

        <section className="section demo reveal" id="demo" aria-labelledby="demo-title">
          <div className="container">
            <p className="section__eyebrow">See it work</p>
            <h2 id="demo-title" className="section__title">Speech to text in any Mac app.</h2>
            <p className="section__deck">
              Hold the hotkey. Speak a full sentence. Release. Your voice is transcribed and typed at the cursor
              &mdash; in an email, a Slack thread, a Notion page, a Google Doc, ChatGPT, or a code editor &mdash;
              without ever leaving your Mac.
            </p>
            <DictationDemo />
          </div>
        </section>

        <section className="section how reveal" id="how-it-works" aria-labelledby="how-title">
          <div className="container">
            <p className="section__eyebrow">Three steps</p>
            <h2 id="how-title" className="section__title">
              How to use voice to text on Mac and MacBook.
            </h2>
            <ul className="how__steps" role="list">
              <li className="how__step">
                <span className="how__index">01</span>
                <span className="how__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-keyboard" /></svg>
                </span>
                <h3 className="how__title">Hold <HotkeyCombo /></h3>
                <p className="how__body">
                  Hold <HotkeyCombo />, speak, release &mdash; words appear at the cursor. Nothing leaves the Mac.
                </p>
              </li>
              <li className="how__step">
                <span className="how__index">02</span>
                <span className="how__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-mic" /></svg>
                </span>
                <h3 className="how__title">Speak naturally</h3>
                <p className="how__body">
                  Full sentences, paragraphs, casual or technical. Punctuation is inferred; you can add it yourself
                  if you prefer.
                </p>
              </li>
              <li className="how__step">
                <span className="how__index">03</span>
                <span className="how__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-arrow-right" /></svg>
                </span>
                <h3 className="how__title">Release &mdash; words are typed</h3>
                <p className="how__body">
                  Let go of the keys. Your text is typed straight into the focused app at the cursor.
                </p>
              </li>
            </ul>
          </div>
        </section>

        <section className="section features reveal" id="features" aria-labelledby="features-title">
          <div className="container">
            <p className="section__eyebrow">What you get</p>
            <h2 id="features-title" className="section__title">Why VoiceToText for Mac speech to text?</h2>
            <p className="section__deck">
              Everything dictation should be on a Mac &mdash; and nothing it shouldn&rsquo;t. Free, offline by
              default, no account, no telemetry.
            </p>
            <ul className="features__grid" role="list">
              <li className="feature-card">
                <div className="feature-card__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-lock" /></svg>
                </div>
                <h3 className="feature-card__title">Your audio never leaves the Mac</h3>
                <p className="feature-card__body">
                  Local models run on-device by default. Zero network calls. No accounts, no servers, no telemetry.
                </p>
              </li>
              <li className="feature-card">
                <div className="feature-card__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-keyboard" /></svg>
                </div>
                <h3 className="feature-card__title">Hold to talk. Release to insert.</h3>
                <p className="feature-card__body">
                  Press <HotkeyCombo />, speak, let go. Text appears at the cursor. No toggles, no accidental
                  cutoffs, no mode to escape.
                </p>
              </li>
              <li className="feature-card">
                <div className="feature-card__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-bolt" /></svg>
                </div>
                <h3 className="feature-card__title">Instant start, minimal battery</h3>
                <p className="feature-card__body">
                  Pure SwiftUI, menu-bar only. Cold-starts in under a second and barely registers in Activity
                  Monitor &mdash; no Electron overhead.
                </p>
              </li>
              <li className="feature-card">
                <div className="feature-card__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-agent" /></svg>
                </div>
                <h3 className="feature-card__title">Faster than typing &mdash; in any app</h3>
                <p className="feature-card__body">
                  A long Slack reply, a thoughtful email, a meeting note, a search query, an AI prompt &mdash;
                  talking is faster than typing. Hold, speak, release.
                </p>
              </li>
              <li className="feature-card">
                <div className="feature-card__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-box" /></svg>
                </div>
                <h3 className="feature-card__title">Switch engines without switching apps</h3>
                <p className="feature-card__body">
                  Parakeet and Whisper run on-device by default. Add an OpenAI key to unlock cloud models. One
                  setting, no reinstall.
                </p>
              </li>
              <li className="feature-card">
                <div className="feature-card__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-apps" /></svg>
                </div>
                <h3 className="feature-card__title">Works in every app that accepts text</h3>
                <p className="feature-card__body">
                  Slack, Mail, Notes, browser address bars, terminals, code editors &mdash; if macOS puts a cursor
                  there, VoiceToText types into it.
                </p>
              </li>
            </ul>
          </div>
        </section>

        <section className="section cloud reveal" id="cloud" aria-labelledby="cloud-title">
          <div className="container">
            <p className="section__eyebrow">Optional</p>
            <h2 id="cloud-title" className="section__title">
              Need higher accuracy? Add an OpenAI key and pick a cloud model.
            </h2>
            <p className="section__deck">
              Local models run by default &mdash; no key required. Paste an OpenAI API key in{" "}
              <strong>Settings &rarr; Cloud</strong> to unlock the models below. Audio only leaves your Mac when a
              cloud model is active.
            </p>
            <ul className="features__grid" role="list">
              <li className="feature-card">
                <div className="feature-card__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-sparkle" /></svg>
                </div>
                <h3 className="feature-card__title">GPT-4o Transcribe</h3>
                <p className="feature-card__body">
                  Best accuracy available. Use it when correctness matters more than cost &mdash; accents,
                  technical jargon, 99+ languages.
                </p>
              </li>
              <li className="feature-card">
                <div className="feature-card__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-bolt" /></svg>
                </div>
                <h3 className="feature-card__title">GPT-4o Mini Transcribe</h3>
                <p className="feature-card__body">
                  The everyday cloud pick. Accuracy close to GPT-4o Transcribe at a fraction of the cost &mdash;
                  good default for high-volume use.
                </p>
              </li>
              <li className="feature-card">
                <div className="feature-card__icon" aria-hidden="true">
                  <svg className="icon icon--lg"><use href="#i-cloud" /></svg>
                </div>
                <h3 className="feature-card__title">Whisper-1</h3>
                <p className="feature-card__body">
                  OpenAI&rsquo;s original hosted model. Lowest cost per minute &mdash; fine for straightforward
                  dictation in major languages.
                </p>
              </li>
            </ul>
            <ul className="cloud__bullets t-caption" role="list">
              <li>Bring your own OpenAI API key &mdash; stored in your Mac&rsquo;s Keychain, never sent anywhere else.</li>
              <li>Audio only leaves your Mac when a cloud model is the active engine. Local models never touch the network.</li>
              <li>Swap back to Parakeet or Whisper-large at any time. No account, no lock-in.</li>
            </ul>
          </div>
        </section>

        <section className="section ai reveal" id="use-cases" aria-labelledby="ai-title">
          <div className="container">
            <p className="section__eyebrow">Use cases</p>
            <h2 id="ai-title" className="section__title">
              Speak in every Mac app &mdash; from Notes and Slack to ChatGPT and Cursor.
            </h2>
            <p className="section__deck">
              Whatever app is in focus gets your words at the cursor. Writing an email, drafting a Slack reply,
              capturing a thought in Apple Notes, prompting ChatGPT, refactoring with Cursor &mdash; same hotkey,
              same speed.
            </p>
            <div className="ai__grid">
              <div className="ai__body">
                <p className="ai__para">
                  A long Slack thread, a meeting note in Apple Notes, a draft in Notion, a Gmail reply, a search in
                  your browser, a ChatGPT question, a Cursor refactor &mdash; same gesture every time. Hold to
                  talk, release to insert. Your voice never leaves the Mac in local mode.
                </p>
                <ul className="ai__apps" role="list" aria-label="Apps people use VoiceToText with">
                  {USE_CASE_APPS.map((name) => (
                    <li key={name} className="ai__app">{name}</li>
                  ))}
                </ul>
              </div>
              <figure className="ai__transcript" aria-label="Example of a voice-dictated Slack message">
                <div className="ai__transcript-chrome" aria-hidden="true">
                  <span className="macos-window__dot" style={{ "--c": "#FF5F57" } as CSSProperties}></span>
                  <span className="macos-window__dot" style={{ "--c": "#FEBC2E" } as CSSProperties}></span>
                  <span className="macos-window__dot" style={{ "--c": "#28C840" } as CSSProperties}></span>
                  <span className="ai__transcript-title">Slack &mdash; #design</span>
                  <span className="ai__transcript-hotkey" aria-hidden="true">
                    <kbd className="keycap keycap--inline" aria-hidden="true">⌥</kbd>
                    <kbd className="keycap keycap--inline" aria-hidden="true">Space</kbd>
                  </span>
                </div>
                <pre className="ai__transcript-body">
                  <code>{`▌ running late to standup — just
▌ finishing a customer call. start
▌ without me, I'll catch up after.`}</code>
                </pre>
                <figcaption className="ai__transcript-caption">
                  <strong>Spoken into Slack in one push.</strong> No window switch, no copy-paste.
                </figcaption>
              </figure>
            </div>
            <div className="ai__cta">
              <a className="btn btn--primary" href={DMG_URL} download>
                <svg className="icon" aria-hidden="true"><use href="#i-download" /></svg>
                <span>Get it free &mdash; download for Mac</span>
              </a>
            </div>
          </div>
        </section>

        <section className="section compare reveal" id="compare" aria-labelledby="compare-title">
          <div className="container">
            <h2 id="compare-title" className="section__title">
              VoiceToText vs. Wispr Flow, Superwhisper, MacWhisper, and Apple Dictation.
            </h2>
            <p className="section__deck">
              Same core idea &mdash; speech to text into any Mac app. Different terms: permanently free, no
              subscription, no account, offline by default, and source code you can read and audit.
            </p>

            <div className="compare__frame" role="region" aria-label="Feature comparison between VoiceToText and competitors">
              <table className="compare__grid">
                <caption className="sr-only">
                  Feature comparison between VoiceToText, Wispr Flow, Superwhisper, MacWhisper, and Apple Dictation
                </caption>
                <thead>
                  <tr>
                    <th scope="col" className="compare__head compare__head--row">Feature</th>
                    <th scope="col" className="compare__head compare__head--ours">VoiceToText</th>
                    {COLUMNS.slice(1).map((c) => (
                      <th key={c} scope="col" className="compare__head">{c}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {COMPARE_ROWS.map((row) => (
                    <tr key={row.label}>
                      <th scope="row" className="compare__row-label">{row.label}</th>
                      {row.cells.map((cell, i) => {
                        const fn = row.footnotes?.[i as 0 | 1 | 2 | 3 | 4];
                        return (
                          <td
                            key={i}
                            className={`compare__cell${i === 0 ? " compare__cell--ours" : ""}`}
                          >
                            <span className={`status status--${row.status[i]}`} aria-hidden="true"></span>
                            {cell}
                            {fn ? (
                              <sup>
                                <a href={`#fn-${fn}`} aria-describedby="compare-footnotes-title">{fn}</a>
                              </sup>
                            ) : null}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="compare__mobile">
              {COLUMNS.map((col, colIdx) => (
                <article
                  key={col}
                  className={`compare__card${colIdx === 0 ? " compare__card--ours" : ""}`}
                >
                  <header className="compare__card-head">
                    <h3>{col}</h3>
                    {colIdx === 0 ? (
                      <span className="chip chip--accent">
                        <span className="chip__dot" aria-hidden="true"></span>
                        Free &amp; open source
                      </span>
                    ) : null}
                  </header>
                  <dl>
                    {COMPARE_ROWS.map((row) => (
                      <div key={row.label} style={{ display: "contents" }}>
                        <dt>{row.label}</dt>
                        <dd>
                          <span className={`status status--${row.status[colIdx]}`} aria-hidden="true"></span>
                          {row.cells[colIdx]}
                        </dd>
                      </div>
                    ))}
                  </dl>
                </article>
              ))}
            </div>

            <h3 id="compare-footnotes-title" className="sr-only">Comparison table footnotes</h3>
            <ol className="compare__footnotes t-caption">
              <li id="fn-1"><sup>1</sup> Wispr Flow is subscription-only; verify current pricing on the vendor site.</li>
              <li id="fn-2"><sup>2</sup> Superwhisper pricing varies between subscription and one-time options &mdash; verify on the vendor site.</li>
              <li id="fn-3"><sup>3</sup> MacWhisper Pro is sold as a one-time purchase, but price varies across sources ($69, $79.99, &euro;59) &mdash; verify on the Gumroad product page.</li>
              <li id="fn-4"><sup>4</sup> Wispr Flow runs inference in the cloud, so on-device Apple Neural Engine acceleration is not applicable.</li>
              <li id="fn-5"><sup>5</sup> MacWhisper&rsquo;s free tier ships a single Whisper engine; multiple model sizes require the Pro upgrade.</li>
            </ol>

            <p className="compare__links t-caption">
              <a href={REPO_URL} target="_blank" rel="noopener">
                Audit the source code <svg className="icon icon--sm" aria-hidden="true"><use href="#i-arrow-right" /></svg>
              </a>
              <span className="compare__sep">&middot;</span>
              <a href={`${REPO_URL}/blob/main/LICENSE`} target="_blank" rel="noopener">
                MIT license <svg className="icon icon--sm" aria-hidden="true"><use href="#i-arrow-right" /></svg>
              </a>
            </p>
          </div>
        </section>

        <section className="section faq reveal" id="faq" aria-labelledby="faq-title">
          <div className="container">
            <p className="section__eyebrow">FAQ</p>
            <h2 id="faq-title" className="section__title">
              Voice to text on Mac &mdash; frequently asked questions.
            </h2>
            <p className="section__deck">
              Answers to what developers, writers, and privacy-conscious users ask before installing this speech to
              text Mac app.
            </p>
            <div className="faq__list">
              {FAQS.map(({ q, a }) => (
                <details key={q} className="faq-item">
                  <summary className="faq-item__q">
                    <span>{q}</span>
                    <svg className="icon faq-item__chevron" aria-hidden="true"><use href="#i-chevron-down" /></svg>
                  </summary>
                  <div className="faq-item__a">{a}</div>
                </details>
              ))}
            </div>
          </div>
        </section>

        <section className="section download reveal" id="download" aria-labelledby="download-title">
          <div className="container download__inner">
            <p className="section__eyebrow">Ready to dictate</p>
            <h2 id="download-title" className="section__title">
              Download VoiceToText &mdash; voice to text for macOS.
            </h2>
            <p className="section__deck">
              One DMG. Drag to Applications. Grant Microphone and Accessibility. Hold <HotkeyCombo /> and speak.
            </p>
            <div className="download__ctas">
              <a className="btn btn--primary btn--lg" href={DMG_URL} download>
                <svg className="icon" aria-hidden="true"><use href="#i-download" /></svg>
                <span>Get it free — download the DMG</span>
              </a>
              <a className="btn btn--secondary btn--lg" href={`${REPO_URL}/releases`} target="_blank" rel="noopener">
                <svg className="icon" aria-hidden="true"><use href="#i-github" /></svg>
                <span>See all releases on GitHub</span>
              </a>
            </div>
            <p className="download__meta t-mono">Free &middot; Open source &middot; macOS 14+ &middot; Apple Silicon</p>
            <ol className="download__steps">
              <li className="download__step">
                <span className="download__step-num">1</span>
                <div>
                  <h3 className="download__step-title">Open the DMG</h3>
                  <p className="download__step-body">
                    Drag <strong>VoiceToText</strong> to <code className="code-inline">/Applications</code>. Takes
                    5 seconds.
                  </p>
                </div>
              </li>
              <li className="download__step">
                <span className="download__step-num">2</span>
                <div>
                  <h3 className="download__step-title">Launch the app</h3>
                  <p className="download__step-body">It lives in the menu bar.</p>
                </div>
              </li>
              <li className="download__step">
                <span className="download__step-num">3</span>
                <div>
                  <h3 className="download__step-title">Grant Microphone and Accessibility</h3>
                  <p className="download__step-body">
                    One-time prompt &mdash; mic hears you, accessibility types into whatever app you&rsquo;re in.
                    Revoke anytime in System Settings.
                  </p>
                </div>
              </li>
              <li className="download__step">
                <span className="download__step-num">4</span>
                <div>
                  <h3 className="download__step-title">Hold <HotkeyCombo />, speak, release.</h3>
                  <p className="download__step-body">Your words are typed at the cursor.</p>
                </div>
              </li>
            </ol>
            <p className="download__perms t-caption">
              <strong>Why two permissions?</strong> Microphone lets the app hear you. Accessibility lets it type
              into whatever app you&rsquo;re in. Both stay on-device. Revoke anytime in System Settings.
            </p>
            <p className="download__reqs t-caption">
              <strong>Requirements:</strong> macOS 14 Sonoma or later &middot; Apple Silicon (M1 or newer).
            </p>
          </div>
        </section>
      </main>

      <footer className="footer" id="footer" aria-labelledby="footer-title">
        <div className="container footer__inner">
          <h2 id="footer-title" className="sr-only">Site footer</h2>
          <div className="footer__brand-block">
            <a className="footer__brand" href="#top" aria-label="VoiceToText home">
              <Image className="brand-mark" src="/app-icon.png" width={28} height={28} alt="" />
              <span>VoiceToText</span>
            </a>
            <p className="footer__tagline">
              Free, local-first dictation for Mac. Open source on GitHub. MIT licensed.
            </p>
            <p className="footer__attribution t-caption">
              Built in public by{" "}
              <a href="https://github.com/gug007" target="_blank" rel="noopener">@gug007</a>.
            </p>
            <p className="footer__privacy t-caption">
              No telemetry. No account. No network calls in local mode.{" "}
              <a className="link" href={REPO_URL} target="_blank" rel="noopener">Audit the source on GitHub &rarr;</a>
            </p>
          </div>
          <nav className="footer__columns" aria-label="Footer">
            <div className="footer__col">
              <h3 className="footer__col-title t-label">Product</h3>
              <ul role="list">
                <li><a href="#features">Features</a></li>
                <li><a href="#cloud">Cloud</a></li>
                <li><a href="#compare">Compare</a></li>
                <li><a href="#faq">FAQ</a></li>
                <li><a href="#download">Download the app</a></li>
              </ul>
            </div>
            <div className="footer__col">
              <h3 className="footer__col-title t-label">Project</h3>
              <ul role="list">
                <li><a href={REPO_URL} target="_blank" rel="noopener">Source on GitHub</a></li>
                <li><a href={`${REPO_URL}/releases`} target="_blank" rel="noopener">Release history</a></li>
                <li><a href={`${REPO_URL}/blob/main/LICENSE`} target="_blank" rel="noopener">MIT license</a></li>
                <li><a href={`${REPO_URL}/issues`} target="_blank" rel="noopener">Report an issue</a></li>
              </ul>
            </div>
            <div className="footer__col">
              <h3 className="footer__col-title t-label">Trust</h3>
              <ul role="list">
                <li><a href="#faq">Privacy answers</a></li>
                <li><a href={REPO_URL} target="_blank" rel="noopener">Audit the source code</a></li>
                <li><a href={`${REPO_URL}/blob/main/LICENSE`} target="_blank" rel="noopener">MIT license</a></li>
                <li><a href={`${REPO_URL}/releases`} target="_blank" rel="noopener">All releases</a></li>
                <li><a href={`${REPO_URL}/issues`} target="_blank" rel="noopener">Report an issue</a></li>
              </ul>
            </div>
          </nav>
          <p className="footer__copyright t-caption">
            &copy; 2026 VoiceToText contributors. Open source on GitHub.
          </p>
        </div>
      </footer>

      <StickyCta />
      <ScrollEffects />
    </>
  );
}
