import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";

import { JsonLd } from "@/components/json-ld";
import { ScrollEffects } from "@/components/scroll-effects";
import { Footer } from "@/components/sections/footer";
import { Nav } from "@/components/sections/nav";
import { StickyCta } from "@/components/sticky-cta";
import { DownloadButton } from "@/components/ui/download-button";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon, type IconName } from "@/components/ui/icon";
import {
  AI_TEXT_MODEL,
  APP_REQUIREMENTS,
  BUILT_IN_ACTIONS,
  MODEL_CATALOG,
  cloudModels,
  defaultModel,
  formatDownloadSize,
  formatPrice,
  formatQuality,
  liveModels,
  localModels,
  modelById,
} from "@/lib/app-facts";
import { AUTHOR_URL, GUIDE_PATH, GUIDE_URL } from "@/lib/constants";
import { formatDisplayDate } from "@/lib/pages";
import {
  GUIDE_H1,
  GUIDE_PUBLISHED,
  GUIDE_UPDATED,
  INDEXABLE_ROBOTS,
  guideArticleJsonLd,
  guideBreadcrumbJsonLd,
  guidePageJsonLd,
  personJsonLd,
} from "@/lib/seo";

import styles from "./guide.module.css";

const TITLE = "How to Use Voice to Text on Mac — Offline, Any App";
const DESCRIPTION =
  "Set up voice to text on your Mac: the shortcut, permissions, review panel keys, offline models for your language, and fixes for common problems.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: GUIDE_PATH },
  robots: INDEXABLE_ROBOTS,
  openGraph: {
    type: "article",
    url: GUIDE_URL,
    title: TITLE,
    description: DESCRIPTION,
    siteName: "VoiceToText",
    locale: "en_US",
    publishedTime: GUIDE_PUBLISHED,
    modifiedTime: GUIDE_UPDATED,
    authors: [AUTHOR_URL],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESCRIPTION,
  },
};

/* Model facts come from lib/app-facts.ts, so the counts and prices here follow
   the app's catalog instead of drifting from it. */
const DEFAULT_MODEL = defaultModel();
const LOCAL = localModels();
const CLOUD = cloudModels();
const CLOUD_PRICES = CLOUD.map((m) => m.pricePerHourUSD);
const CHEAPEST_CLOUD = formatPrice({ pricePerHourUSD: Math.min(...CLOUD_PRICES) });
const PRICIEST_CLOUD = formatPrice({ pricePerHourUSD: Math.max(...CLOUD_PRICES) });
const LIVE_COUNT = liveModels().length;
const LIVE_TEXT_COUNT = liveModels().filter((m) => m.showsLiveText).length;
const LARGE_V3 = modelById("whisper-large-v3");
const TURBO = modelById("whisper-large-v3-turbo");

const NUMBER_WORDS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"];
const spell = (n: number) => NUMBER_WORDS[n] ?? String(n);
const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/** A keyboard key with a spoken name, the way HotkeyCombo does it. */
function Key({ glyph, name }: { glyph: string; name: string }) {
  return (
    <>
      <span className="sr-only">{name}</span>
      <kbd className="keycap keycap--inline" aria-hidden="true">{glyph}</kbd>
    </>
  );
}

type GuideStep = {
  title: ReactNode;
  body: ReactNode;
};

const STEPS: GuideStep[] = [
  {
    title: "Install VoiceToText",
    body: (
      <p>
        Download the DMG, open it, and drag <strong>VoiceToText</strong> into your Applications folder.
        The app is signed and notarized for macOS. On first launch it asks for microphone access and starts
        downloading the default model.
      </p>
    ),
  },
  {
    title: "Grant two permissions",
    body: (
      <p>
        Microphone lets the app hear you. Accessibility lets it start recording from the global shortcut and
        paste the finished text where your cursor is; macOS asks for it the first time you dictate. You can
        revoke either permission in System Settings.
      </p>
    ),
  },
  {
    title: <>Put the cursor anywhere and press <HotkeyCombo /></>,
    body: (
      <p>
        Open Mail, Notes, Slack, a browser, a terminal, or any other Mac app. Click where you want the text,
        press the shortcut, and speak naturally.
      </p>
    ),
  },
  {
    title: "Watch the recording card",
    body: (
      <p>
        A small floating card appears with a live level meter and a timer, without taking focus from your
        app. Press the shortcut again or click Finish when you’re done, or press <Key glyph="Esc" name="Escape" />{" "}
        to throw the take away. If the model is still downloading or loading, the card shows its progress
        first.
      </p>
    ),
  },
  {
    title: "Review, then paste",
    body: (
      <>
        <p>
          The text opens in a review panel where you can edit it before anything is pasted:
        </p>
        <dl className={styles.keys}>
          <dt><Key glyph="Return" name="Return" /></dt>
          <dd>Paste at the cursor</dd>
          <dt><Key glyph="⇧" name="Shift" /><Key glyph="Return" name="Return" /></dt>
          <dd>New line</dd>
          <dt><HotkeyCombo /></dt>
          <dd>Your shortcut again also pastes</dd>
          <dt><Key glyph="⌘" name="Command" /><Key glyph="R" name="R" /></dt>
          <dd>Resume: record another take, inserted at the caret</dd>
          <dt><Key glyph="⌘1" name="Command 1" />–<Key glyph="⌘9" name="Command 9" /></dt>
          <dd>Run an AI action, if you’ve turned any on</dd>
          <dt>Undo button</dt>
          <dd>Appears after an AI action; steps back one action at a time</dd>
          <dt><Key glyph="Esc" name="Escape" /></dt>
          <dd>Cancel and discard the take</dd>
        </dl>
        <p>
          VoiceToText pastes rather than types: it saves your clipboard, puts the text on it, presses ⌘V for
          you, and puts your previous clipboard back a moment later. Turn review off and the text pastes as
          soon as it’s ready.
        </p>
      </>
    ),
  },
];

type Choice = {
  icon: IconName;
  title: string;
  body: ReactNode;
};

const PERMISSIONS: Choice[] = [
  {
    icon: "mic",
    title: "Microphone",
    body: "Required to record your voice. Enable VoiceToText in System Settings → Privacy & Security → Microphone; you can revoke access at any time.",
  },
  {
    icon: "lock",
    title: "Accessibility",
    body: "Required to start dictation, for Esc to cancel, and to paste the transcript into another app. VoiceToText does not use it to read your screen or log keystrokes.",
  },
  {
    icon: "keyboard",
    title: "Input Monitoring, optional",
    body: "Only the standalone Right Control shortcut needs Input Monitoring. The default Option+Space shortcut does not require this third permission.",
  },
];

const MODELS: Choice[] = [
  {
    icon: "bolt",
    title: `${DEFAULT_MODEL.name}, the default`,
    body: `The recommended local model and the one downloaded first (${formatDownloadSize(DEFAULT_MODEL) ?? "a few hundred MB"}). It covers English and 24 other European languages and recognizes which one you’re speaking. There is no language to set.`,
  },
  {
    icon: "sparkle",
    title: "Whisper Large v3 and Turbo",
    body: `Local Whisper models transcribe English in VoiceToText. Large v3 has the highest quality score of the local models (${LARGE_V3 ? formatQuality(LARGE_V3) : "8.0"}) but takes longer; Turbo (${TURBO ? formatQuality(TURBO) : "7.5"}) is quicker.`,
  },
  {
    icon: "box",
    title: "Whisper Small, Base, and Tiny",
    body: "Smaller downloads, from roughly 250 MB down to under 50 MB, for Macs short on disk space. They make noticeably more mistakes, and they also transcribe English.",
  },
  {
    icon: "cloud",
    title: "Cloud models, with your key",
    body: `${capitalize(spell(CLOUD.length))} optional OpenAI and ElevenLabs models detect the language on their side (90 to 99+ languages). ${capitalize(spell(LIVE_COUNT))} are live models, and with ${spell(LIVE_TEXT_COUNT)} of them text appears while you speak, word by word or phrase by phrase. Audio goes to the provider, billed to your key at ${CHEAPEST_CLOUD} to ${PRICIEST_CLOUD}.`,
  },
];

const CHOICES: Choice[] = [
  {
    icon: "keyboard",
    title: "Toggle or hold to talk",
    body: (
      <>
        “Press to toggle” is the default: press once to start, again to stop. In Settings → Shortcut, switch
        Recording mode to “Hold to record” to talk only while the key is down. “Esc cancels dictation” is on by
        default; turn it off there if Esc should reach the app you’re in.
      </>
    ),
  },
  {
    icon: "keyboard",
    title: "Pick a shortcut that suits you",
    body: (
      <>
        Record any key with at least one modifier (⌘ ⌥ ⌃ ⇧), a function key from F1 to F20 on its own, or Right
        Control on its own, which needs Input Monitoring. A second, optional Conversation shortcut starts and
        stops meeting recording.
      </>
    ),
  },
  {
    icon: "sparkle",
    title: "Review or instant paste",
    body: (
      <>
        “Review before pasting” is on by default, so you can edit, resume, or cancel before anything lands.
        Turn it off in Settings → General and the text pastes the moment transcription finishes. A take that
        lost audio when the microphone dropped out still opens review so you can check it.
      </>
    ),
  },
  {
    icon: "agent",
    title: "AI Actions, when you want them",
    body: (
      <>
        {BUILT_IN_ACTIONS.length} built-in actions ({BUILT_IN_ACTIONS.join(", ")}) plus your own, each a name and
        an instruction. All are off by default: turn them on in Settings → Actions and add an OpenAI key in
        Cloud. They run from the review panel, so keep Review before pasting on to use them. Running one sends
        the transcript text to OpenAI (<code>{AI_TEXT_MODEL}</code>), billed to your key.
      </>
    ),
  },
  {
    icon: "apps",
    title: "Run it from the menu bar",
    body: (
      <>
        The menu bar item starts and stops dictation and meeting recording. In Settings → General, turn off
        Show in Dock to keep VoiceToText in the menu bar only, pick System, Light, or Dark appearance, and
        choose whether it opens at login (it’s on after the first launch).
      </>
    ),
  },
  {
    icon: "bolt",
    title: "Trigger it from other tools",
    body: (
      <>
        Raycast, Shortcuts, Stream Deck, or a script can open <code>voicetotext://toggle</code>,{" "}
        <code>start</code>, <code>stop</code>, or <code>cancel</code>. In Terminal,{" "}
        <code>open -g voicetotext://toggle</code> starts dictation without bringing VoiceToText forward, so the
        text lands in the app you’re using. The URL scheme controls dictation only.
      </>
    ),
  },
  {
    icon: "box",
    title: "Keep, search, or skip history",
    body: (
      <>
        Each dictation is saved on this Mac with its audio and transcript. In History you can search
        transcripts, star favorites, play audio back, and re-transcribe with another model. Turn off Save
        recordings to stop keeping dictations. History holds your newest 200 recordings, meetings included, and
        favorites are not exempt.
      </>
    ),
  },
  {
    icon: "cloud",
    title: "Compare models in the Models pane",
    body: (
      <>
        The Models pane lists all {MODEL_CATALOG.length} models, {LOCAL.length} on your Mac and {CLOUD.length} in
        the cloud, with a 1–10 quality score based on published third-party word error rates and the hourly
        price of each cloud model. Filter by On this Mac or Cloud and sort by quality.
      </>
    ),
  },
];

const TROUBLESHOOTING: { title: string; body: ReactNode }[] = [
  {
    title: "The shortcut does nothing",
    body: "Confirm VoiceToText is enabled under Accessibility; Settings → General → Permissions shows what’s missing. If another app owns the same combination, record a different shortcut in Settings → Shortcut.",
  },
  {
    title: "Right Control does nothing",
    body: "The standalone Right Control shortcut needs Input Monitoring in addition to Accessibility. Enable VoiceToText under System Settings → Privacy & Security → Input Monitoring.",
  },
  {
    title: "Nothing was pasted",
    body: "Click into a text field first and check that Accessibility is enabled. The text arrives as a paste, so fields that block pasting, such as some password fields, won’t receive it. Unless you turned off Save recordings, the transcript is still in History, where you can copy it.",
  },
  {
    title: "The model is still downloading",
    body: "The default model starts downloading when VoiceToText first opens; other local models download from the Models pane. If you dictate before one is ready, the recording card shows download and loading progress. The download needs an internet connection once; after that Parakeet works offline. Loading a Whisper model also needs a connection, after every launch. Press Esc to stop waiting.",
  },
  {
    title: "The words come out in the wrong language",
    body: "There is no language setting. Parakeet covers 25 European languages automatically. For other languages, choose an OpenAI or ElevenLabs cloud model, which detects the language. Local Whisper models currently transcribe English, so other languages can come out translated or garbled.",
  },
  {
    title: "Saying “comma” or “new line” types the word",
    body: "VoiceToText has no voice commands. The model adds punctuation from how you speak, so words like “comma”, “period”, or “new line” are typed as words, and filler words are kept. Press Shift+Return in the review panel for a line break, or turn on the Clean transcript or Fix grammar AI action in Settings → Actions (it needs your OpenAI key), which turns spoken cues like “comma” and “new line” into formatting.",
  },
  {
    title: "Transcription is slow or inaccurate",
    body: "Try Parakeet for local speed, or Whisper Large v3 for the most accurate English on your Mac. Speak close to the microphone and cut background noise. VoiceToText records from the macOS default input, which you choose in System Settings → Sound.",
  },
  {
    title: "My AirPods switched mid-sentence",
    body: "When the microphone changes in the middle of a dictation, capture restarts on its own and the take continues. If it can’t, what was already captured is still transcribed, and the review panel tells you if audio dropped out for a second or more.",
  },
  {
    title: "Transcription failed",
    body: "The failure card keeps your audio. Retry runs the same recording again. If a cloud model has no key, Add API Key opens Settings → Cloud; for a permission problem, Open Settings takes you to the right place.",
  },
  {
    title: "“Recording too short” or “No speech detected”",
    body: "Takes under half a second, or with no speech in them, are dropped so the model doesn’t invent text. Watch the level meter on the recording card: if it barely moves, check the input device in System Settings → Sound.",
  },
];

export default function VoiceToTextGuidePage() {
  return (
    <>
      <JsonLd data={guideArticleJsonLd} />
      <JsonLd data={guidePageJsonLd} />
      <JsonLd data={guideBreadcrumbJsonLd} />
      <JsonLd data={personJsonLd} />

      <Nav linkPrefix="/" current={GUIDE_PATH} />
      <main id="main" tabIndex={-1}>
        <article>
          <header className="section guide-hero" id="top" aria-labelledby="guide-title">
            <div className="container guide-hero__inner">
              <nav className="breadcrumb" aria-label="Breadcrumb">
                <ol role="list">
                  <li><Link href="/">Home</Link></li>
                  <li aria-current="page">Mac voice-to-text guide</li>
                </ol>
              </nav>
              <p className="hero__eyebrow">
                <span className="hero__eyebrow-dot" aria-hidden="true" />
                Practical guide · about 8 minutes
              </p>
              <h1 id="guide-title" className="hero__title guide-hero__title">
                {GUIDE_H1}
              </h1>
              <p className="hero__lead guide-hero__lead">
                Install once, press a global shortcut, speak, and your words are pasted wherever the cursor is.
                The default model works offline on Apple Silicon after a{" "}
                <span style={{ whiteSpace: "nowrap" }}>one-time</span> download.
              </p>
              <div className="hero__ctas">
                <DownloadButton placement="guide_hero" />
                <Link className="btn btn--secondary btn--lg" href="/#demo">
                  <span>Watch the dictation demo</span>
                  <Icon name="arrow-right" />
                </Link>
              </div>
              <p className="guide__meta">
                Written by <a className="link" href={AUTHOR_URL} rel="author">Gurgen Abagyan</a>, the
                developer of VoiceToText · <time dateTime={GUIDE_UPDATED}>Updated {formatDisplayDate(GUIDE_UPDATED)}</time>
              </p>
            </div>
          </header>

          <section className="section guide-section" id="quick-start" aria-labelledby="quick-start-title">
            <div className="container guide__container">
              <p className="section__eyebrow">Quick start</p>
              <h2 id="quick-start-title" className="section__title">Set up Mac voice typing in five steps.</h2>
              <p className="section__deck">
                VoiceToText works system-wide rather than inside one editor. Once the permissions are granted,
                the same shortcut works in nearly any app that accepts a paste.
              </p>
              <ol className="guide__steps" role="list">
                {STEPS.map(({ title, body }, index) => (
                  <li key={index} className="guide__step">
                    <span className="guide__step-number" aria-hidden="true">{index + 1}</span>
                    <div>
                      <h3>{title}</h3>
                      <div className={styles.stepBody}>{body}</div>
                    </div>
                  </li>
                ))}
              </ol>
              <aside className="guide__note" aria-label="System requirements">
                <Icon name="bolt" size="lg" />
                <div>
                  <strong>Before you install</strong>
                  <p>
                    Current builds require {APP_REQUIREMENTS.os} and an {APP_REQUIREMENTS.processor} Mac.
                    Keep an internet connection for the first model download; after that the default Parakeet
                    model works offline. Whisper models need a connection each time they load. The app checks
                    GitHub for new versions and asks before installing one.
                  </p>
                </div>
              </aside>
            </div>
          </section>

          <section className="section how" id="permissions" aria-labelledby="permissions-title">
            <div className="container guide__container">
              <p className="section__eyebrow">Mac permissions</p>
              <h2 id="permissions-title" className="section__title">
                Grant only the permissions your shortcut needs.
              </h2>
              <p className="section__deck">
                The default setup needs Microphone and Accessibility. Input Monitoring is requested only when
                you choose Right Control as a standalone shortcut. Recording meetings adds Screen Recording,
                which is used for system audio only.
              </p>
              <div className="guide__choices">
                {PERMISSIONS.map(({ icon, title, body }) => (
                  <article key={title} className="guide__choice">
                    <span className="feature-card__icon" aria-hidden="true"><Icon name={icon} size="lg" /></span>
                    <h3>{title}</h3>
                    <p>{body}</p>
                  </article>
                ))}
              </div>
            </div>
          </section>

          <section className="section guide-section" id="models-and-languages" aria-labelledby="models-title">
            <div className="container guide__container">
              <p className="section__eyebrow">Models &amp; languages</p>
              <h2 id="models-title" className="section__title">
                Choose an offline speech-to-text model for your language and Mac.
              </h2>
              <p className="section__deck">
                VoiceToText has {spell(LOCAL.length)} local models. Each downloads once, then transcribes on your
                Mac without sending audio anywhere. Parakeet also works with the network off, while loading a
                Whisper model needs a connection. There is no language setting, so pick a model that covers the
                language you speak.
              </p>
              <div className={`guide__choices ${styles.grid2}`}>
                {MODELS.map(({ icon, title, body }) => (
                  <article key={title} className="guide__choice">
                    <span className="feature-card__icon" aria-hidden="true"><Icon name={icon} size="lg" /></span>
                    <h3>{title}</h3>
                    <p>{body}</p>
                  </article>
                ))}
              </div>
              <p className="guide__context-link">
                Deciding between the two local families? Read{" "}
                <Link className="link" href="/whisper-vs-parakeet-mac">Whisper vs Parakeet on Mac</Link>. For a
                privacy walkthrough, see how{" "}
                <Link className="link" href="/offline-speech-to-text-mac">
                  offline speech to text works on Mac
                </Link>.
              </p>
            </div>
          </section>

          <section className="section how" id="choose-your-flow" aria-labelledby="flow-title">
            <div className="container guide__container">
              <p className="section__eyebrow">Make it yours</p>
              <h2 id="flow-title" className="section__title">Choose the dictation flow that feels natural.</h2>
              <p className="section__deck">
                Start with the defaults, then change only what removes friction from your own workflow.
              </p>
              <div className={`guide__choices ${styles.grid2}`}>
                {CHOICES.map(({ icon, title, body }) => (
                  <article key={title} className={`guide__choice ${styles.card}`}>
                    <span className="feature-card__icon" aria-hidden="true"><Icon name={icon} size="lg" /></span>
                    <h3>{title}</h3>
                    <p>{body}</p>
                  </article>
                ))}
              </div>
            </div>
          </section>

          <section className="section guide-section" id="where-it-works" aria-labelledby="apps-title">
            <div className="container guide__container">
              <p className="section__eyebrow">Use it anywhere</p>
              <h2 id="apps-title" className="section__title">Dictate into Mail, Notes, Slack, browsers, and coding tools.</h2>
              <p className="section__deck">
                The focused text field receives the transcript. That includes documents, chat apps, browser
                search boxes, terminals, ChatGPT, Claude Code, Cursor, and nearly any native or web app that
                accepts a paste.
              </p>
              <ul className="guide__app-list" role="list" aria-label="Example supported apps">
                {["Mail", "Notes", "Slack", "Notion", "Google Docs", "ChatGPT", "Cursor", "Terminal"].map((app) => (
                  <li key={app}>{app}</li>
                ))}
              </ul>
              <p className="guide__context-link">
                Need longer-form capture? VoiceToText can also{" "}
                <Link className="link" href="/meeting-recording">record and transcribe meetings on your Mac</Link>.
              </p>
            </div>
          </section>

          <section className="section faq" id="troubleshooting" aria-labelledby="troubleshooting-title">
            <div className="container guide__container">
              <p className="section__eyebrow">Troubleshooting</p>
              <h2 id="troubleshooting-title" className="section__title">Fix common Mac dictation setup problems.</h2>
              <p className="section__deck">
                Check permissions and the selected model first; most shortcut, paste, language, and offline
                issues come from one of those settings.
              </p>
              <div className={`guide__troubleshooting ${styles.trouble}`}>
                {TROUBLESHOOTING.map(({ title, body }) => (
                  <article key={title}>
                    <h3>{title}</h3>
                    <p>{body}</p>
                  </article>
                ))}
              </div>
              <p className="guide__context-link">
                For model, privacy, and language details, read the{" "}
                <Link className="link" href="/#faq">complete VoiceToText FAQ</Link>.
              </p>
            </div>
          </section>

          <section className="section guide-section" id="related-guides" aria-labelledby="related-guides-title">
            <div className="container guide__container">
              <p className="section__eyebrow">Continue learning</p>
              <h2 id="related-guides-title" className="section__title">Choose your next Mac voice workflow.</h2>
              <div className={`guide__choices ${styles.grid2}`}>
                <article className="guide__choice">
                  <h3>
                    <Link className="link" href="/offline-speech-to-text-mac">
                      Keep speech to text offline
                    </Link>
                  </h3>
                  <p>Compare local processing, model downloads, privacy boundaries, and offline limitations.</p>
                </article>
                <article className="guide__choice">
                  <h3>
                    <Link className="link" href="/voice-to-text-for-coding">
                      Dictate into coding tools
                    </Link>
                  </h3>
                  <p>Use voice for prompts and implementation notes in Cursor, Claude Code, ChatGPT, and terminals.</p>
                </article>
                <article className="guide__choice">
                  <h3>
                    <Link className="link" href="/meeting-recording">
                      Record and transcribe meetings
                    </Link>
                  </h3>
                  <p>Capture microphone and system audio together, transcribed on your Mac by default.</p>
                </article>
                <article className="guide__choice">
                  <h3>
                    <Link className="link" href="/compare">
                      Compare Mac voice-to-text apps
                    </Link>
                  </h3>
                  <p>See how VoiceToText stacks up against Apple Dictation, Wispr Flow, Superwhisper, and others.</p>
                </article>
              </div>
            </div>
          </section>

          <section className="section download" id="download" aria-labelledby="guide-download-title">
            <div className="container download__inner">
              <p className="section__eyebrow">Ready to speak</p>
              <h2 id="guide-download-title" className="section__title">Try voice to text in the app you already use.</h2>
              <p className="section__deck">
                Free, local by default, and source available on GitHub. Download the DMG and dictate your first sentence in a few minutes.
              </p>
              <div className="download__ctas">
                <DownloadButton placement="guide_footer" />
                <Link className="btn btn--secondary btn--lg" href="/#features">
                  <span>Explore key features</span>
                  <Icon name="arrow-right" />
                </Link>
              </div>
            </div>
          </section>
        </article>
      </main>
      <Footer linkPrefix="/" />
      <StickyCta />
      <ScrollEffects />
    </>
  );
}
