import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";

import { JsonLd } from "@/components/json-ld";
import { ScrollEffects } from "@/components/scroll-effects";
import { Footer } from "@/components/sections/footer";
import { Nav } from "@/components/sections/nav";
import { StickyCta } from "@/components/sticky-cta";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon, type IconName } from "@/components/ui/icon";
import { AUTHOR_URL, DMG_URL, GUIDE_PATH, GUIDE_URL } from "@/lib/constants";
import {
  GUIDE_PUBLISHED,
  guideArticleJsonLd,
  guideBreadcrumbJsonLd,
  guidePageJsonLd,
  personJsonLd,
} from "@/lib/seo";

const TITLE = "How to Use Voice to Text on Mac — Offline, Any App";
const DESCRIPTION =
  "Set up voice to text on your Mac in minutes. Learn the shortcut, permissions, review flow, offline models, and how to dictate into any app.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: GUIDE_PATH },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
      "max-video-preview": -1,
    },
  },
  openGraph: {
    type: "article",
    url: GUIDE_URL,
    title: TITLE,
    description: DESCRIPTION,
    siteName: "VoiceToText",
    locale: "en_US",
    publishedTime: GUIDE_PUBLISHED,
    modifiedTime: GUIDE_PUBLISHED,
    authors: [AUTHOR_URL],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESCRIPTION,
  },
};

type GuideStep = {
  title: ReactNode;
  body: ReactNode;
};

const STEPS: GuideStep[] = [
  {
    title: "Install VoiceToText",
    body: (
      <>
        Download the DMG, open it, and drag <strong>VoiceToText</strong> into your Applications folder.
        The app is signed and notarized for macOS.
      </>
    ),
  },
  {
    title: "Grant two permissions",
    body: (
      <>
        Microphone lets the app hear you. Accessibility lets it paste the finished transcript into the app
        where your cursor is. You can revoke either permission in System Settings.
      </>
    ),
  },
  {
    title: <>Put the cursor anywhere and press <HotkeyCombo /></>,
    body: (
      <>
        Open Mail, Notes, Slack, a browser, a terminal, or any other Mac app. Click where you want the text,
        press the shortcut, and speak naturally. Press <kbd className="keycap keycap--inline">Esc</kbd> to
        cancel.
      </>
    ),
  },
  {
    title: "Stop, review, and paste",
    body: (
      <>
        Press the shortcut again. Edit the transcript if needed, then press Return to paste it at the cursor.
        If you prefer zero friction, turn off review and the text will paste immediately.
      </>
    ),
  },
];

type Choice = {
  icon: IconName;
  title: string;
  body: string;
};

const CHOICES: Choice[] = [
  {
    icon: "keyboard",
    title: "Toggle or hold to talk",
    body: "Tap the shortcut once to start and again to stop, or switch it to push-to-talk and hold the key only while speaking.",
  },
  {
    icon: "lock",
    title: "Local by default",
    body: "Choose Parakeet or Whisper and transcription runs on your Mac after the model download. Your recording never leaves the device.",
  },
  {
    icon: "sparkle",
    title: "Review or instant paste",
    body: "Keep the review panel for edits and AI actions, or disable it when speed matters more than a final check.",
  },
];

const TROUBLESHOOTING = [
  {
    title: "The shortcut does nothing",
    body: "Open VoiceToText Settings and confirm the shortcut is enabled. If another app owns the same combination, rebind it to a different key or use Right Control.",
  },
  {
    title: "The app can hear you but cannot type",
    body: "Re-open System Settings → Privacy & Security → Accessibility and enable VoiceToText. This permission is what lets the app paste at the focused cursor.",
  },
  {
    title: "Transcription is slow or inaccurate",
    body: "Try Parakeet for speed, Whisper Large v3 for offline accuracy, or a smaller Whisper model if memory is tight. A cloud model is optional when you need maximum accuracy or live words.",
  },
] as const;

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
                Practical guide · about 5 minutes
              </p>
              <h1 id="guide-title" className="hero__title guide-hero__title">
                How to use voice to text on Mac — in any app.
              </h1>
              <p className="hero__lead guide-hero__lead">
                Install once, press a global shortcut, speak, and your words appear wherever the cursor is.
                The default models work offline on Apple Silicon.
              </p>
              <div className="hero__ctas">
                <a
                  className="btn btn--primary btn--lg"
                  href={DMG_URL}
                  data-analytics-event="download_click"
                  data-analytics-placement="guide_hero"
                >
                  <Icon name="download" />
                  <span>Download for Mac — free</span>
                </a>
                <Link className="btn btn--secondary btn--lg" href="/#demo">
                  <span>Watch the dictation demo</span>
                  <Icon name="arrow-right" />
                </Link>
              </div>
              <p className="guide__meta">
                Written by <a className="link" href={AUTHOR_URL} rel="author">Gurgen Abagyan</a>, the
                developer of VoiceToText · <time dateTime={GUIDE_PUBLISHED}>Updated July 11, 2026</time>
              </p>
            </div>
          </header>

          <section className="section guide-section reveal" id="quick-start" aria-labelledby="quick-start-title">
            <div className="container guide__container">
              <p className="section__eyebrow">Quick start</p>
              <h2 id="quick-start-title" className="section__title">Set up Mac voice typing in four steps.</h2>
              <p className="section__deck">
                VoiceToText works system-wide rather than inside one editor. Once the permissions are granted,
                the same shortcut works anywhere macOS shows a text cursor.
              </p>
              <ol className="guide__steps" role="list">
                {STEPS.map(({ title, body }, index) => (
                  <li key={index} className="guide__step">
                    <span className="guide__step-number" aria-hidden="true">{index + 1}</span>
                    <div>
                      <h3>{title}</h3>
                      <p>{body}</p>
                    </div>
                  </li>
                ))}
              </ol>
              <aside className="guide__note" aria-label="System requirements">
                <Icon name="bolt" size="lg" />
                <div>
                  <strong>Before you install</strong>
                  <p>Current builds require macOS 15.0 or later and an Apple Silicon Mac (M1 or newer).</p>
                </div>
              </aside>
            </div>
          </section>

          <section className="section how reveal" id="choose-your-flow" aria-labelledby="flow-title">
            <div className="container guide__container">
              <p className="section__eyebrow">Make it yours</p>
              <h2 id="flow-title" className="section__title">Choose the dictation flow that feels natural.</h2>
              <p className="section__deck">
                Start with the defaults, then change only what removes friction from your own workflow.
              </p>
              <div className="guide__choices">
                {CHOICES.map(({ icon, title, body }) => (
                  <article key={title} className="guide__choice">
                    <span className="feature-card__icon" aria-hidden="true"><Icon name={icon} size="lg" /></span>
                    <h3>{title}</h3>
                    <p>{body}</p>
                  </article>
                ))}
              </div>
            </div>
          </section>

          <section className="section guide-section reveal" id="where-it-works" aria-labelledby="apps-title">
            <div className="container guide__container">
              <p className="section__eyebrow">Use it anywhere</p>
              <h2 id="apps-title" className="section__title">Dictate into Mail, Notes, Slack, browsers, and coding tools.</h2>
              <p className="section__deck">
                The focused text field receives the transcript. That includes documents, chat apps, browser
                search boxes, terminals, ChatGPT, Claude Code, Cursor, and nearly any native or web app.
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

          <section className="section faq reveal" id="troubleshooting" aria-labelledby="troubleshooting-title">
            <div className="container guide__container">
              <p className="section__eyebrow">Troubleshooting</p>
              <h2 id="troubleshooting-title" className="section__title">Three quick checks solve most setup issues.</h2>
              <div className="guide__troubleshooting">
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

          <section className="section download reveal" id="download" aria-labelledby="guide-download-title">
            <div className="container download__inner">
              <p className="section__eyebrow">Ready to speak</p>
              <h2 id="guide-download-title" className="section__title">Try voice to text in the app you already use.</h2>
              <p className="section__deck">
                Free, open source, and local by default. Download the DMG and dictate your first sentence in a few minutes.
              </p>
              <div className="download__ctas">
                <a
                  className="btn btn--primary btn--lg"
                  href={DMG_URL}
                  data-analytics-event="download_click"
                  data-analytics-placement="guide_footer"
                >
                  <Icon name="download" />
                  <span>Download for Mac — free</span>
                </a>
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
