import type { Metadata } from "next";
import Link from "next/link";

import { JsonLd } from "@/components/json-ld";
import { ScrollEffects } from "@/components/scroll-effects";
import { Footer } from "@/components/sections/footer";
import { Nav } from "@/components/sections/nav";
import { StickyCta } from "@/components/sticky-cta";
import { ExternalLink } from "@/components/ui/external-link";
import { FeatureCard } from "@/components/ui/feature-card";
import { Icon, type IconName } from "@/components/ui/icon";
import { TrafficLights } from "@/components/ui/traffic-lights";
import { WaveBars } from "@/components/ui/wave-bars";
import { DMG_URL, RELEASES_URL } from "@/lib/constants";
import {
  MEETING_PATH,
  MEETING_URL,
  meetingBreadcrumbJsonLd,
  meetingFaqEntries,
  meetingFaqPageJsonLd,
  meetingPageJsonLd,
  personJsonLd,
} from "@/lib/seo";

const TITLE = "Record & Transcribe Meetings on Mac — Free · VoiceToText";
const DESCRIPTION =
  "Free, open-source meeting recorder for Mac. Record your mic + system audio (Zoom, Meet, Teams, FaceTime) and transcribe the call on-device. No bot, no fees.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: MEETING_PATH },
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
    type: "website",
    siteName: "VoiceToText",
    url: MEETING_URL,
    title: TITLE,
    description: DESCRIPTION,
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: "Record & transcribe meetings on Mac — free & on-device",
    description:
      "Record your mic and the call's system audio together, then transcribe on-device. No meeting bot, no subscription. Free & open source.",
  },
};

const RECORD_FROM = [
  "Zoom",
  "Google Meet",
  "Microsoft Teams",
  "FaceTime",
  "Webex",
  "Slack huddles",
  "Discord",
  "Any audio",
] as const;

const TRANSCRIPT = `00:00  Let's kick off the weekly sync.
00:05  Launch status — design is signed
       off, eng is on the last endpoint.
00:14  Any blockers before Friday?
00:19  None on my side. I'll send notes
       right after this call.`;

const HERO_META = ["Signed & notarized", "Mic + system audio", "On-device by default"];

type Step = {
  index: string;
  icon: IconName;
  title: string;
  body: string;
};

const STEPS: Step[] = [
  {
    index: "01",
    icon: "mic",
    title: "Start recording",
    body: "Open Conversations in VoiceToText and click Start Recording. The first time, macOS asks once for Microphone and Screen Recording — that's what lets it hear you and capture system audio.",
  },
  {
    index: "02",
    icon: "apps",
    title: "Keep working",
    body: "It records in the background, streaming straight to disk. Switch apps, take notes, share your screen — the recording keeps running with barely any footprint.",
  },
  {
    index: "03",
    icon: "sparkle",
    title: "Stop → transcript",
    body: "Stop, and the recording is transcribed with your chosen model — on-device by default, long calls in segments — and saved to your history with the audio you can replay and a transcript you can copy.",
  },
];

type Capability = {
  icon: IconName;
  title: string;
  body: string;
};

const CAPABILITIES: Capability[] = [
  {
    icon: "mic",
    title: "Mic + system audio",
    body: "Records both directions at once through ScreenCaptureKit, so everyone on the call is captured — not just your side.",
  },
  {
    icon: "lock",
    title: "Private by default",
    body: "Local models transcribe the recording on your Mac. With a local engine, your audio never leaves the device — transcription makes zero network calls.",
  },
  {
    icon: "apps",
    title: "A history you can replay",
    body: "Recordings are saved on-device with audio and transcript — a rolling history of your 200 most recent. Play back, copy, favorite; deletes come with an undo, and a crash-interrupted recording is recovered on the next launch.",
  },
  {
    icon: "sparkle",
    title: "Regenerate & compare",
    body: "Re-run the transcript with a more accurate model and keep both versions side by side, so you can pick the better one and drop the other.",
  },
  {
    icon: "box",
    title: "Import a file",
    body: "Already have a recording? Drop in any audio or video file — VoiceToText extracts the audio and transcribes it the same way.",
  },
  {
    icon: "bolt",
    title: "No bot, no subscription",
    body: "Nothing joins your call and nobody is billed per minute. Free and open source, with the source on GitHub to audit.",
  },
];

const PRIVACY_BULLETS = [
  "Microphone records your voice; Screen Recording is how macOS exposes system audio through ScreenCaptureKit — VoiceToText never records the screen, only the audio. Accessibility is only used by dictation, not by meeting recording.",
  "With a local model (Whisper or Parakeet on the Apple Neural Engine), the recording is transcribed entirely on your Mac and never leaves the device.",
  "Cloud transcription is opt-in: only if you pick an OpenAI or ElevenLabs model is audio sent — directly to that provider under your own API key. VoiceToText is never in that path.",
  "Recordings and transcripts live in Application Support on your Mac. Delete any of them anytime, right from the history — with a 5-second undo if you slip.",
];

export default function MeetingRecordingPage() {
  return (
    <>
      <JsonLd data={meetingPageJsonLd} />
      <JsonLd data={meetingFaqPageJsonLd} />
      <JsonLd data={meetingBreadcrumbJsonLd} />
      <JsonLd data={personJsonLd} />

      <Nav linkPrefix="/" current="/meeting-recording" />
      <main id="main" tabIndex={-1}>
        {/* Hero */}
        <section className="section hero" id="top" aria-labelledby="mr-hero-title">
          <WaveBars />
          <div className="container hero__inner">
            <nav className="breadcrumb" aria-label="Breadcrumb">
              <ol role="list">
                <li><Link href="/">Home</Link></li>
                <li aria-current="page">Meeting recording</li>
              </ol>
            </nav>
            <p className="hero__eyebrow">
              <span className="hero__eyebrow-dot" aria-hidden="true" />
              Meeting recording · macOS
            </p>
            <h1 id="mr-hero-title" className="hero__title">
              Record &amp; transcribe meetings
              <br />
              <span className="hero__title-accent">on your Mac. Free.</span>
            </h1>
            <p className="hero__lead">
              Capture your mic and the call’s system audio together — then get an on-device transcript.
              No bot in the meeting.
            </p>
            <div className="hero__ctas">
              <a
                className="btn btn--primary btn--lg"
                href={DMG_URL}
                data-analytics-event="download_click"
                data-analytics-placement="meeting_hero"
              >
                <Icon name="download" />
                <span>Download for Mac — free</span>
              </a>
              <a className="btn btn--secondary btn--lg" href="#how-it-captures">
                <span>See how recording works</span>
                <Icon name="arrow-right" />
              </a>
            </div>
            <p className="hero__meta">
              {HERO_META.map((item, i) => (
                <span key={item} style={{ display: "inline-flex", alignItems: "center", gap: "var(--space-3)" }}>
                  {item}
                  {i < HERO_META.length - 1 ? <span className="hero__meta-sep" aria-hidden="true" /> : null}
                </span>
              ))}
            </p>
            <p className="hero__meta-sub t-caption">
              macOS 15.0+ · Apple Silicon (M1+) · Microphone and Screen Recording permission required.
            </p>
            <p className="hero__subcopy">
              VoiceToText records Zoom, Google Meet, Microsoft Teams, FaceTime, or any call playing through
              your Mac, keeps running in the background while you work, and transcribes everything locally on
              the Apple Neural Engine by default — saved to your on-device history.
            </p>
          </div>
        </section>

        {/* How it captures the call */}
        <section className="section ai reveal" id="how-it-captures" aria-labelledby="mr-capture-title">
          <div className="container">
            <p className="section__eyebrow">How it captures the call</p>
            <h2 id="mr-capture-title" className="section__title">
              Both sides of the conversation — without a bot in the meeting.
            </h2>
            <p className="section__deck">
              Most meeting tools join your call as a participant. VoiceToText doesn’t. It records locally from
              macOS itself: your microphone plus the system audio coming out of your Mac, mixed into one
              recording.
            </p>
            <div className="ai__grid">
              <div className="ai__body">
                <p className="ai__para">
                  Start a recording from the Conversations pane, then carry on. VoiceToText streams the audio
                  straight to disk in the background — no RAM bloat, no window to babysit — and transcribes it
                  the moment you stop, on-device by default. It works with whatever is making sound:
                </p>
                <ul className="ai__apps" role="list" aria-label="Apps VoiceToText records audio from">
                  {RECORD_FROM.map((name) => (
                    <li key={name} className="ai__app">{name}</li>
                  ))}
                </ul>
              </div>
              <figure className="ai__transcript" aria-label="Example meeting transcript recorded on a Mac">
                <div className="ai__transcript-chrome" aria-hidden="true">
                  <TrafficLights />
                  <span className="ai__transcript-title">Conversations — Team sync</span>
                </div>
                <pre className="ai__transcript-body"><code>{TRANSCRIPT}</code></pre>
                <figcaption className="ai__transcript-caption">
                  <strong>Recorded and transcribed on-device.</strong> Mic + system audio, saved to history.
                </figcaption>
              </figure>
            </div>
          </div>
        </section>

        {/* How it works */}
        <section className="section how reveal" id="how-it-works" aria-labelledby="mr-how-title">
          <div className="container">
            <p className="section__eyebrow">Three steps</p>
            <h2 id="mr-how-title" className="section__title">
              How to record a meeting on your Mac.
            </h2>
            <ul className="how__steps" role="list">
              {STEPS.map(({ index, icon, title, body }) => (
                <li key={index} className="how__step">
                  <span className="how__index">{index}</span>
                  <span className="how__icon" aria-hidden="true"><Icon name={icon} size="lg" /></span>
                  <h3 className="how__title">{title}</h3>
                  <p className="how__body">{body}</p>
                </li>
              ))}
            </ul>
          </div>
        </section>

        {/* Capabilities */}
        <section className="section features reveal" id="capabilities" aria-labelledby="mr-features-title">
          <div className="container">
            <p className="section__eyebrow">What you get</p>
            <h2 id="mr-features-title" className="section__title">
              A full meeting recorder, built into your dictation app.
            </h2>
            <p className="section__deck">
              No second subscription, no plugin in the call, no audio shipped to someone else’s server. Just a
              native Mac app that records, transcribes, and remembers — on your Mac.
            </p>
            <ul className="features__grid" role="list">
              {CAPABILITIES.map(({ icon, title, body }) => (
                <FeatureCard key={title} icon={icon} title={title}>{body}</FeatureCard>
              ))}
            </ul>
          </div>
        </section>

        {/* Privacy & permissions */}
        <section className="section cloud reveal" id="privacy" aria-labelledby="mr-privacy-title">
          <div className="container">
            <p className="section__eyebrow">Permissions &amp; privacy</p>
            <h2 id="mr-privacy-title" className="section__title">
              Your meetings stay on your Mac.
            </h2>
            <p className="section__deck">
              Recording a conversation is sensitive, so VoiceToText keeps it local by default. Here is exactly
              what it needs and where your audio goes.
            </p>
            <ul className="cloud__bullets t-caption" role="list">
              {PRIVACY_BULLETS.map((bullet) => (
                <li key={bullet}>{bullet}</li>
              ))}
            </ul>
          </div>
        </section>

        {/* FAQ */}
        <section className="section faq reveal" id="faq" aria-labelledby="mr-faq-title">
          <div className="container">
            <p className="section__eyebrow">FAQ</p>
            <h2 id="mr-faq-title" className="section__title">
              Recording meetings on Mac — common questions.
            </h2>
            <div className="faq__list">
              {meetingFaqEntries.map(({ question, answer }) => (
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

        {/* Download */}
        <section className="section download reveal" id="download" aria-labelledby="mr-download-title">
          <div className="container download__inner">
            <p className="section__eyebrow">Ready to record</p>
            <h2 id="mr-download-title" className="section__title">
              Start recording your meetings — free.
            </h2>
            <p className="section__deck">
              One DMG, drag to Applications, grant Microphone and Screen Recording. Then record any call and
              get an on-device transcript.
            </p>
            <div className="download__ctas">
              <a
                className="btn btn--primary btn--lg"
                href={DMG_URL}
                data-analytics-event="download_click"
                data-analytics-placement="meeting_footer"
              >
                <Icon name="download" />
                <span>Download for Mac — free</span>
              </a>
              <ExternalLink className="btn btn--secondary btn--lg" href={RELEASES_URL}>
                <Icon name="github" />
                <span>See all releases on GitHub</span>
              </ExternalLink>
            </div>
            <p className="download__meta t-mono">Free · Open source · macOS 15.0+ · Apple Silicon</p>
            <p className="download__reqs t-caption">
              The same app also does hotkey dictation into any text field.{" "}
              <Link className="link" href="/#features">See everything VoiceToText does →</Link>
            </p>
          </div>
        </section>
      </main>
      <Footer linkPrefix="/" />
      <StickyCta />
      <ScrollEffects />
    </>
  );
}
