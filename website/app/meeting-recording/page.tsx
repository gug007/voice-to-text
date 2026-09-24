import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";

import { JsonLd } from "@/components/json-ld";
import { ScrollEffects } from "@/components/scroll-effects";
import { Footer } from "@/components/sections/footer";
import { Nav } from "@/components/sections/nav";
import { StickyCta } from "@/components/sticky-cta";
import { DownloadButton } from "@/components/ui/download-button";
import { ExternalLink } from "@/components/ui/external-link";
import { ConversationMockup } from "@/components/ui/conversation-mockup";
import { FeatureCard } from "@/components/ui/feature-card";
import { Icon, type IconName } from "@/components/ui/icon";
import { TrafficLights } from "@/components/ui/traffic-lights";
import { WaveBars } from "@/components/ui/wave-bars";
import { AI_TEXT_MODEL, APP_REQUIREMENTS, MODEL_CATALOG } from "@/lib/app-facts";
import { AUTHOR_URL, RELEASES_URL } from "@/lib/constants";
import { formatDisplayDate } from "@/lib/pages";
import {
  INDEXABLE_ROBOTS,
  MEETING_PATH,
  MEETING_PUBLISHED,
  MEETING_UPDATED,
  MEETING_URL,
  meetingBreadcrumbJsonLd,
  meetingFaqEntries,
  meetingFaqPageJsonLd,
  meetingPageJsonLd,
  personJsonLd,
} from "@/lib/seo";

import styles from "./meeting.module.css";

const TITLE = "Free Meeting Recorder for Mac — System Audio & Transcript";
const DESCRIPTION =
  "Record Zoom, Meet, Teams, and FaceTime on Mac: mic + system audio, no bot. Transcribe on-device by default; optional AI summaries and action items.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: MEETING_PATH },
  robots: INDEXABLE_ROBOTS,
  openGraph: {
    type: "article",
    siteName: "VoiceToText",
    url: MEETING_URL,
    title: TITLE,
    description: DESCRIPTION,
    locale: "en_US",
    publishedTime: MEETING_PUBLISHED,
    modifiedTime: MEETING_UPDATED,
    authors: [AUTHOR_URL],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESCRIPTION,
  },
};

const MODEL_COUNT = MODEL_CATALOG.length;

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

const TRANSCRIPT = [
  { who: "Maya", said: "Let’s kick off the weekly sync." },
  { who: "Leo", said: "Design is signed off, and the team is on the last endpoint." },
  { who: "Maya", said: "Any blockers before Friday?" },
  { who: "Leo", said: "None. I’ll send the notes right after this call." },
] as const;

const HERO_META = ["Signed & notarized", "Mic + system audio", "No bot in the call"];

type Step = {
  index: string;
  title: string;
  body: ReactNode;
};

const STEPS: Step[] = [
  {
    index: "01",
    title: "Pick a transcription model",
    body: (
      <p>
        Conversations has its own <strong>Transcription model</strong> setting. The default, “Same as
        dictation”, uses your dictation model, which is on-device Parakeet on a fresh install. Pick GPT-4o
        Transcribe Diarize when you want speaker labels. You set this once.
      </p>
    ),
  },
  {
    index: "02",
    title: "Start recording",
    body: (
      <>
        <p>Start whichever way is closest:</p>
        <ul className={styles.ways} role="list">
          <li>
            <strong>Start Recording</strong> in the Conversations pane.
          </li>
          <li>
            <strong>Start Conversation Recording</strong> from the menu bar, which then shows a running clock.
          </li>
          <li>
            Your <strong>Conversation shortcut</strong>, from any app. It has no default key; set one in
            Settings → Shortcut.
          </li>
        </ul>
        <p>
          The first time, macOS asks for Screen Recording; Microphone was already granted when you first
          opened the app. Enable VoiceToText in System Settings → Privacy &amp; Security → Screen Recording,
          then start the recording again. Screen Recording is how an app gets system audio; VoiceToText
          records only the audio, never the screen.
        </p>
      </>
    ),
  },
  {
    index: "03",
    title: "Stop & Transcribe",
    body: (
      <p>
        Carry on with the call while the audio streams to disk. When it ends, press Stop &amp; Transcribe (or
        your shortcut again). The transcript is made after you stop, so there is no live transcript during
        the call. Long calls are transcribed in parts, with progress shown.
      </p>
    ),
  },
  {
    index: "04",
    title: "Find it in History",
    body: (
      <p>
        The recording lands in Conversations and History with its audio and transcript. Play it back, copy
        the transcript, name the speakers if you used GPT-4o Transcribe Diarize, or generate a summary and
        action items from the sparkles menu.
      </p>
    ),
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
    body: "Your microphone and everything playing on the Mac are captured together through ScreenCaptureKit and mixed into one recording, so the whole call is there, not just your side.",
  },
  {
    icon: "lock",
    title: "On-device by default",
    body: "Out of the box, conversations are transcribed by the local Parakeet model and the audio stays on your Mac. It leaves only if you choose a cloud model for the transcription.",
  },
  {
    icon: "apps",
    title: "Search every transcript",
    body: "Type in History’s Search transcripts field to find a word across transcripts, summaries, action items, and speaker names. Play recordings back, copy them, star favorites, and undo a delete within 5 seconds.",
  },
  {
    icon: "sparkle",
    title: "Regenerate and compare",
    body: `Re-run any recording with any of the ${MODEL_COUNT} models and keep both transcripts side by side, so you can pick the better one and remove the other.`,
  },
  {
    icon: "box",
    title: "Import a file",
    body: "Click Upload File… or drag one audio or video file onto Conversations. MP3, M4A, WAV, AIFF, FLAC, MP4, and MOV work; MKV, WebM, and AVI don’t. The audio is extracted and transcribed like a live recording.",
  },
  {
    icon: "download",
    title: "Crash-safe capture",
    body: "Audio is written to disk as you record. After a crash, force quit, or power loss, the recording is repaired and filed in History on the next launch. It arrives without a transcript: choose Regenerate to transcribe it.",
  },
  {
    icon: "bolt",
    title: "Long calls, in parts",
    body: "Recordings over 12 minutes are transcribed in parts of about 10 minutes, each cut at the quietest nearby moment to avoid splitting a word. With a local model, memory use stays flat however long the call ran.",
  },
  {
    icon: "agent",
    title: "No bot, no subscription",
    body: "Nothing joins your call, and VoiceToText never charges by the minute. Local transcription has no fee; cloud models and AI summaries are billed by the provider to your own API key.",
  },
];

const PRIVACY_BULLETS = [
  "Microphone records your voice. Screen Recording is how macOS exposes system audio through ScreenCaptureKit; VoiceToText never records the screen, only the audio. Accessibility is used only by dictation, not by meeting recording.",
  "With a local model (Parakeet, the default, or Whisper), the recording is transcribed on your Mac and the audio never leaves it.",
  "Audio goes to a provider only when a cloud model transcribes it: an OpenAI model you choose in Conversations, or a cloud dictation model while the setting is “Same as dictation”. It goes directly to that provider under your own API key. VoiceToText has no server in that path.",
  "Summaries, action items, and custom prompts send the transcript text, never the audio, to OpenAI, and only when you generate one.",
  "Recordings and transcripts live in ~/Library/Application Support/VoiceToText/History. Delete any of them from History, with a 5-second undo if you slip.",
  "History keeps your newest 200 recordings. Dictations and conversations share that limit and favorites are not exempt, so the oldest recordings are deleted, audio included, once you pass it.",
];

const SPEAKER_WORKFLOW = [
  {
    title: "Choose the diarizing model",
    body: "In Conversations, set Transcription model to GPT-4o Transcribe Diarize and add your OpenAI API key in Cloud, or regenerate a saved recording with it. The audio is sent to OpenAI, at a list price of $0.36 per hour billed to your key.",
  },
  {
    title: "See who said what",
    body: "The transcript comes back as turns labeled Speaker 1, Speaker 2, and so on, instead of one uninterrupted block of meeting text. Turns carry no timestamps. Recordings over 12 minutes are sent in parts, and only the first four speakers are carried from part to part, so anyone else may get a new number in a later part. Give both labels the same name to merge them.",
  },
  {
    title: "Replace labels with names",
    body: "Open Name speakers on the recording and type a name for each label. Giving two labels the same name merges their turns. Names appear when you copy the transcript, in summaries and action items, and in search.",
  },
] as const;

const INSIGHTS = [
  {
    title: "Summary",
    body: "A short overview, then each topic in the order it came up, with any open questions at the end. It is written in the meeting’s language, and the model is told not to add names, numbers, or decisions nobody mentioned.",
  },
  {
    title: "Action Items",
    body: "A checklist of what people agreed to do. Each item is a task, with an owner and a due date only when someone actually said them; the model is told never to fill them in. Tick items off as you go, and copy the list as a Markdown checklist:",
    example: "- [ ] Finish the last endpoint — Leo (before Friday)",
  },
  {
    title: "Your own format",
    body: "Custom prompt opens Format with AI. Ask for meeting minutes, a follow-up email, or a translation, and the result gets its own tab, named for what it is. Each recording holds up to 3 custom tabs, and your recent prompts are remembered.",
  },
] as const;

function PersonGlyph() {
  return (
    <svg viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.3" aria-hidden="true">
      <circle cx="6" cy="4" r="2.2" />
      <path d="M1.8 11c.5-2.2 2.2-3.4 4.2-3.4s3.7 1.2 4.2 3.4" strokeLinecap="round" />
    </svg>
  );
}

function ClockGlyph() {
  return (
    <svg viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.3" aria-hidden="true">
      <circle cx="6" cy="6" r="4.8" />
      <path d="M6 3.4V6l1.8 1.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

const MOCK_ITEMS = [
  { task: "Send the meeting notes", owner: "Leo", due: "after this call", done: true },
  { task: "Finish the last endpoint", owner: "Leo", due: "before Friday", done: false },
  { task: "Share the design sign-off", owner: "Maya", due: null, done: false },
] as const;

/** Decorative: a saved conversation with its Action Items tab open. Every
 *  behaviour it shows is also described in the section's text. */
function InsightsMock() {
  return (
    <div aria-hidden="true">
      <div className={styles.mock}>
        <div className={styles.mockHead}>
          <span className={styles.mockPlay}>
            <svg viewBox="0 0 10 10" fill="currentColor">
              <path d="M1.5 1v8l7-4z" />
            </svg>
          </span>
          <span className={styles.mockDate}>Today at 3:42 PM</span>
          <span className={styles.mockBadge}>Conversation</span>
          <span className={styles.mockSpacer} />
          <span className={styles.mockMono}>32:10</span>
        </div>
        <div className={styles.mockTabs}>
          <span className={styles.mockTab}>Transcript</span>
          <span className={styles.mockTab}>Summary</span>
          <span className={`${styles.mockTab} ${styles.mockTabActive}`}>
            Action Items <span className={styles.mockCount}>3</span>
          </span>
          <span className={styles.mockTab}>Minutes</span>
        </div>
        <ul className={styles.mockList}>
          {MOCK_ITEMS.map(({ task, owner, due, done }) => (
            <li key={task} className={done ? `${styles.mockItem} ${styles.mockItemDone}` : styles.mockItem}>
              <span className={styles.mockBox}>
                {done ? (
                  <svg viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M2.5 6.3 5 8.6l4.5-5" />
                  </svg>
                ) : null}
              </span>
              <span>
                <span className={styles.mockTask}>{task}</span>
                <span className={styles.mockMeta}>
                  <span className={styles.mockChip}>
                    <PersonGlyph />
                    {owner}
                  </span>
                  {due ? (
                    <span className={styles.mockChip}>
                      <ClockGlyph />
                      {due}
                    </span>
                  ) : null}
                </span>
              </span>
            </li>
          ))}
        </ul>
        <div className={styles.mockFoot}>
          <span>3 action items · 1 done</span>
          <span className={styles.mockSpacer} />
          <span className={styles.mockCopy}>Copy</span>
        </div>
      </div>
    </div>
  );
}

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
              Record &amp; transcribe meetings{" "}
              <br />
              <span className="hero__title-accent">on your Mac. Free.</span>
            </h1>
            <p className="hero__lead">
              Capture your mic and the call’s system audio together, with no bot joining the meeting. Transcribe
              on your Mac by default, then get a summary and action items when you want them.
            </p>
            <div className="hero__ctas">
              <DownloadButton placement="meeting_hero" />
              <a className="btn btn--secondary btn--lg" href="#how-it-captures">
                <span>See how recording works</span>
                <Icon name="arrow-right" />
              </a>
            </div>
            <ul className={`hero__meta ${styles.heroMeta}`} role="list">
              {HERO_META.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
            <p className={`guide__meta ${styles.heroByline}`}>
              <span>{APP_REQUIREMENTS.short} ·</span>{" "}
              <time dateTime={MEETING_UPDATED}>Updated {formatDisplayDate(MEETING_UPDATED)}</time>
            </p>
            <div className={styles.heroStage}>
              <ConversationMockup />
            </div>
          </div>
        </section>

        {/* How it captures the call */}
        <section className="section ai" id="how-it-captures" aria-labelledby="mr-capture-title">
          <div className="container">
            <p className="section__eyebrow">How it captures the call</p>
            <h2 id="mr-capture-title" className="section__title">
              Both sides of the conversation, without a bot in the meeting.
            </h2>
            <p className="section__deck">
              Many meeting tools join your call as a participant. VoiceToText doesn’t. It records from macOS
              itself: your microphone plus the system audio coming out of your Mac, mixed into one recording.
            </p>
            <div className="ai__grid">
              <div className="ai__body">
                <p className="ai__para">
                  Start a recording from the Conversations pane, the menu bar, or your own shortcut, then carry
                  on. The audio streams to disk while you record, so an hour-long call isn’t held in memory, and it
                  is transcribed when you stop. It works with whatever is making sound, including Zoom, Google
                  Meet, Microsoft Teams and FaceTime, and keeps running in the background while you work. Every
                  recording lands in a searchable history on your Mac:
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
                  <span className="ai__transcript-title">Conversations — Today at 3:42 PM</span>
                </div>
                <ul className={styles.transcriptBody} role="list">
                  {TRANSCRIPT.map(({ who, said }, i) => (
                    <li key={i}>
                      <b>{who}:</b> {said}
                    </li>
                  ))}
                </ul>
                <figcaption className="ai__transcript-caption">
                  <strong>Optional speaker-separated transcript.</strong> GPT-4o Transcribe Diarize sends audio
                  directly to OpenAI under your API key; rename the detected speakers in History.
                </figcaption>
              </figure>
            </div>
          </div>
        </section>

        <section className="section how" id="speaker-diarization" aria-labelledby="speaker-title">
          <div className="container">
            <p className="section__eyebrow">Speaker diarization</p>
            <h2 id="speaker-title" className="section__title">
              Separate speakers, then give the labels real names.
            </h2>
            <p className="section__deck">
              Local Parakeet and Whisper models produce one continuous transcript. When you need to tell
              speakers apart, the optional GPT-4o Transcribe Diarize model adds labeled turns that you can
              rename.
            </p>
            <div className="guide__choices">
              {SPEAKER_WORKFLOW.map(({ title, body }) => (
                <article key={title} className="guide__choice">
                  <h3>{title}</h3>
                  <p>{body}</p>
                </article>
              ))}
            </div>
            <aside className="guide__note" aria-label="Speaker diarization privacy note">
              <Icon name="cloud" size="lg" />
              <div>
                <strong>Diarization is cloud-only</strong>
                <p>
                  It needs an OpenAI API key and sends the recording directly to OpenAI. Keep a local model
                  selected when the audio must stay on your Mac.
                </p>
              </div>
            </aside>
          </div>
        </section>

        {/* After the call: AI insights */}
        <section className="section" id="after-the-call" aria-labelledby="mr-after-title">
          <div className="container">
            <p className="section__eyebrow">After the call</p>
            <h2 id="mr-after-title" className="section__title">
              After the call: summary, action items, your own format.
            </h2>
            <p className="section__deck">
              Open the sparkles menu on any recording and choose Generate summary, Generate action items, or
              Custom prompt. Conversation rows also show Summary, Action items, and Custom buttons until the
              first result exists. Results sit in tabs beside the transcript and are saved with the recording.
            </p>
            <div className={styles.afterGrid}>
              <ul className={styles.insightList} role="list">
                {INSIGHTS.map((item) => (
                  <li key={item.title}>
                    <h3>{item.title}</h3>
                    <p>
                      {item.body}
                      {"example" in item ? (
                        <>
                          {" "}
                          <code>{item.example}</code>
                        </>
                      ) : null}
                    </p>
                  </li>
                ))}
              </ul>
              <div>
                <InsightsMock />
                <p className={styles.mockCaption}>
                  A saved conversation with its Action Items tab open. Maya’s task has no due date because
                  nobody gave one.
                </p>
              </div>
            </div>
            <div className={styles.scope}>
              <span className={styles.scopeIcon} aria-hidden="true">
                <Icon name="cloud" size="lg" />
              </span>
              <div>
                <h3>Optional, and clear about what leaves your Mac</h3>
                <ul className={styles.scopeList} role="list">
                  <li>
                    Nothing runs until you ask. Summaries, action items, and custom prompts need your own OpenAI
                    API key, added in Cloud.
                  </li>
                  <li>
                    They run on OpenAI’s <code>{AI_TEXT_MODEL}</code> and send the transcript text, with speaker
                    names, to OpenAI. The audio is not sent. OpenAI bills your key.
                  </li>
                  <li>
                    Transcription can still stay local. The summary step only ever sees the text.
                  </li>
                  <li>
                    Long transcripts are handled in parts and combined, so a two-hour meeting gets one summary
                    and one list.
                  </li>
                  <li>
                    If you regenerate the transcript, your summary and action items are kept and marked as out
                    of date, with a button to run them again.
                  </li>
                  <li>
                    Results are searchable from History and can be copied. There is no file export, calendar,
                    or task-app integration.
                  </li>
                </ul>
              </div>
            </div>
            <p className={styles.inlineLink}>
              Weighing this against a dedicated notes app? See how VoiceToText compares with{" "}
              <Link className="link" href="/granola-alternative">Granola for bot-free AI meeting notes</Link>.
            </p>
          </div>
        </section>

        {/* How to record */}
        <section className="section how" id="how-it-works" aria-labelledby="mr-how-title">
          <div className="container">
            <p className="section__eyebrow">Four steps</p>
            <h2 id="mr-how-title" className="section__title">
              How to record a meeting on your Mac.
            </h2>
            <ol className={`how__steps ${styles.steps}`} role="list">
              {STEPS.map(({ index, title, body }) => (
                <li key={index} className="how__step">
                  <span className="how__index" aria-hidden="true">{index}</span>
                  <h3 className="how__title">{title}</h3>
                  <div className={styles.stepBody}>{body}</div>
                </li>
              ))}
            </ol>
            <p className={styles.sectionNote}>
              Not sure which model to pick? Parakeet covers English and 24 other European languages on your Mac;
              local Whisper models transcribe English. For other languages, choose an OpenAI model.{" "}
              <Link className="link" href="/whisper-vs-parakeet-mac">Compare Whisper and Parakeet on Mac</Link>.
            </p>
          </div>
        </section>

        {/* Capabilities */}
        <section className="section features" id="capabilities" aria-labelledby="mr-features-title">
          <div className="container">
            <p className="section__eyebrow">What you get</p>
            <h2 id="mr-features-title" className="section__title">
              A full meeting recorder, built into your dictation app.
            </h2>
            <p className="section__deck">
              No second subscription and no plugin in the call. Keep transcription on your Mac with a local
              model, or choose a cloud model when you want one of its features. Here is{" "}
              <Link className="link" href="/compare">how VoiceToText compares with other Mac apps</Link>.
            </p>
            <ul className="features__grid" role="list">
              {CAPABILITIES.map(({ icon, title, body }) => (
                <FeatureCard key={title} icon={icon} title={title}>{body}</FeatureCard>
              ))}
            </ul>
          </div>
        </section>

        {/* Privacy & permissions */}
        <section className="section section--band cloud" id="privacy" aria-labelledby="mr-privacy-title">
          <div className="container">
            <p className="section__eyebrow">Permissions &amp; privacy</p>
            <h2 id="mr-privacy-title" className="section__title">
              Local transcription keeps your meetings on your Mac.
            </h2>
            <p className="section__deck">
              Recording a conversation is sensitive, so the default setup keeps it local. Here is exactly what
              VoiceToText needs, where your audio goes, and how long it is kept.
            </p>
            <div className={`${styles.scope} ${styles.privacyScope}`}>
              <span className={styles.scopeIcon} aria-hidden="true">
                <Icon name="lock" size="lg" />
              </span>
              <ul className={styles.scopeList} role="list">
                {PRIVACY_BULLETS.map((bullet) => (
                  <li key={bullet}>{bullet}</li>
                ))}
              </ul>
            </div>
          </div>
        </section>

        <section className="section" id="related-guides" aria-labelledby="meeting-related-title">
          <div className="container">
            <p className="section__eyebrow">Compare and keep going</p>
            <h2 id="meeting-related-title" className="section__title">
              See the alternatives, or use the same app beyond meetings.
            </h2>
            <div className="guide__choices">
              <article className="guide__choice">
                <h3>
                  <Link className="link" href="/granola-alternative">
                    VoiceToText vs Granola
                  </Link>
                </h3>
                <p>Bot-free AI meeting notes: local transcription and your own key, compared with Granola.</p>
              </article>
              <article className="guide__choice">
                <h3>
                  <Link className="link" href="/wispr-flow-alternative">
                    VoiceToText vs Wispr Flow
                  </Link>
                </h3>
                <p>Dictation, meeting notes, pricing, and where your audio is processed, side by side.</p>
              </article>
              <article className="guide__choice">
                <h3>
                  <Link className="link" href="/compare">
                    Compare Mac voice apps
                  </Link>
                </h3>
                <p>Every comparison in one place, with dated sources for the other apps’ claims.</p>
              </article>
              <article className="guide__choice">
                <h3>
                  <Link className="link" href="/how-to-use-voice-to-text-on-mac">
                    Set up voice to text on Mac
                  </Link>
                </h3>
                <p>Grant the right permissions, choose a shortcut and model, and dictate into any text field.</p>
              </article>
              <article className="guide__choice">
                <h3>
                  <Link className="link" href="/offline-speech-to-text-mac">
                    Keep transcription offline
                  </Link>
                </h3>
                <p>Understand local model downloads, supported workflows, and when audio stays on your Mac.</p>
              </article>
              <article className="guide__choice">
                <h3>
                  <Link className="link" href="/voice-to-text-for-coding">
                    Dictate into coding tools
                  </Link>
                </h3>
                <p>Use the global shortcut for prompts and implementation notes in AI and development tools.</p>
              </article>
            </div>
          </div>
        </section>

        {/* FAQ */}
        <section className="section faq" id="faq" aria-labelledby="mr-faq-title">
          <div className="container">
            <p className="section__eyebrow">FAQ</p>
            <h2 id="mr-faq-title" className="section__title">
              Recording meetings on Mac: common questions.
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
        <section className="section download" id="download" aria-labelledby="mr-download-title">
          <div className="container download__inner">
            <p className="section__eyebrow">Ready to record</p>
            <h2 id="mr-download-title" className="section__title">
              Start recording your meetings, free.
            </h2>
            <p className="section__deck">
              One DMG, drag to Applications, grant Microphone and Screen Recording. Then record any call and
              get a transcript made on your Mac.
            </p>
            <div className="download__ctas">
              <DownloadButton placement="meeting_footer" />
              <ExternalLink
                className="btn btn--secondary btn--lg"
                href={RELEASES_URL}
                data-analytics-event="github_outbound"
                data-analytics-placement="meeting_footer"
              >
                <Icon name="github" />
                <span>See all releases on GitHub</span>
              </ExternalLink>
            </div>
            <p className="download__meta t-mono">Free · Source on GitHub · {APP_REQUIREMENTS.short}</p>
            <p className="download__reqs t-caption">
              The same app also does hotkey dictation into any text field.{" "}
              <Link className="link" href="/#features" style={{ whiteSpace: "nowrap" }}>See everything VoiceToText does →</Link>
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
