import Link from "next/link";

import {
  AI_TEXT_MODEL,
  APP_REQUIREMENTS,
  defaultModel,
  formatPrice,
  joinNames,
  localModels,
  MICROPHONE_SETTING,
  type ModelFact,
} from "@/lib/app-facts";
import { RELEASES_URL, REPO_URL } from "@/lib/constants";
import { CONVERSATION_CLOUD_MODELS, countWord, DIARIZE_MODEL, pricePerHour } from "@/lib/seo";

import type { SeoLandingConfig } from "./seo-landing";

// Two spokes of /meeting-recording. Every VoiceToText claim here was checked
// against the app source on 2026-11-13:
//   Meetings/MeetingRecorder.swift        ScreenCaptureKit mic + system audio, own audio excluded, streamed WAV
//   Meetings/MeetingController.swift      start/stop paths, interruption salvage, permission errors
//   Audio/StreamingWAVWriter.swift        16-bit mono WAV at 16 kHz (AppConstants.targetSampleRate)
//   Settings/MicrophoneCard.swift         the microphone picker, Settings → General
//   Settings/RecordingRow.swift           "Regenerate with" lists every non-live model
// Model names, prices and counts come from lib/app-facts.ts so a catalog
// change can't leave a stale number behind. Neither page names another
// vendor's prices: the "how pricing usually works" cards describe categories.

const LOCAL = localModels();
const DEFAULT_MODEL = defaultModel();
const LOCAL_WHISPER = LOCAL.filter((m) => m.name.startsWith("Whisper"));

const CLOUD_BY_PRICE = [...CONVERSATION_CLOUD_MODELS].sort((a, b) => a.pricePerHourUSD - b.pricePerHourUSD);
const CHEAPEST_CLOUD = CLOUD_BY_PRICE[0];
const PRICIEST_CLOUD = CLOUD_BY_PRICE[CLOUD_BY_PRICE.length - 1];
const MEETING_PROVIDERS = [...new Set(CONVERSATION_CLOUD_MODELS.map((m) => m.provider))];
const MEETING_PROVIDERS_OR = new Intl.ListFormat("en", { style: "long", type: "disjunction" }).format(
  MEETING_PROVIDERS,
);

/** "GPT Transcribe on OpenAI ($0.27/hr)": local and cloud Whisper share names, so the provider is always said. */
const cloudModelLabel = (m: ModelFact) => `${m.name} on ${m.provider} (${formatPrice(m)})`;

/** Conversations are kept as 16-bit mono WAV at 16 kHz: 32,000 bytes a second. */
const STORAGE_MB_PER_HOUR = Math.round((16_000 * 2 * 3600) / 1_000_000);

const DIARIZE_HALF_HOUR = `$${(DIARIZE_MODEL.pricePerHourUSD / 2).toFixed(2)}`;

/* ---------- /record-meetings-without-a-bot-mac ---------- */

export const noBotMeetingConfig: SeoLandingConfig = {
  path: "/record-meetings-without-a-bot-mac",
  parent: { name: "Meeting recording", path: "/meeting-recording" },
  title: "Record Zoom, Meet & Teams Calls on Mac Without a Bot",
  description:
    "Record and transcribe Zoom, Google Meet and Microsoft Teams calls on a Mac with no bot joining: mic + system audio, on-device transcripts, free.",
  breadcrumb: "Without a bot",
  eyebrow: "Meeting recording guide",
  readingTime: "8 min",
  h1: "Record Zoom, Google Meet and Teams calls on your Mac, with no bot in the meeting.",
  lead:
    "A meeting bot records by joining your call as an extra participant. VoiceToText records from your Mac instead: it captures your microphone and the sound your Mac plays, so both sides of the call are recorded and transcribed, and nobody new appears in the participant list.",
  heroPoints: [
    "Nothing joins the call",
    "Zoom, Meet, Teams, FaceTime",
    "On-device transcripts by default",
    "Free · no account",
  ],
  summaryTitle: "The short answer",
  summary: (
    <>
      Yes, a Mac can record a call without anything joining it. VoiceToText uses Apple’s ScreenCaptureKit to
      record your microphone and everything the Mac plays, mixes them into one recording, and transcribes it
      on your Mac when you stop. It works the same in Zoom, Google Meet, Microsoft Teams, FaceTime, Webex,
      Discord and any other app that plays sound, whether you host the call or join it. There is no bot,
      plugin, browser extension or meeting-app account involved, and the app is free with no sign-up.
    </>
  ),
  sections: [
    {
      id: "by-call-app",
      eyebrow: "App by app",
      title: "One recording method for every call app, because it never enters the call.",
      intro:
        "VoiceToText doesn’t connect to Zoom, Google or Microsoft. It records what your Mac hears and plays, so the steps are the same everywhere; only a few details differ.",
      cards: [
        {
          title: "Zoom",
          body:
            "Use the Zoom app or Zoom in a browser. VoiceToText doesn’t use Zoom’s Record button or cloud recording, connects to no Zoom account and installs nothing in Zoom. Start recording just before you join and stop when you leave.",
        },
        {
          title: "Google Meet",
          body:
            "Meet runs in a browser tab, and the tab’s sound is system audio like any other app’s. There is no Chrome extension to install, and it works the same in Safari, Chrome or any other browser. Mute other tabs that play sound, because they would be recorded too.",
        },
        {
          title: "Microsoft Teams",
          body:
            "Works with the Teams app or Teams on the web, for meetings and one-to-one calls alike. Nothing is added to Teams, so there is no Teams app for an admin to approve. On a Mac your employer manages, check that its policy lets you turn on Screen & System Audio Recording for VoiceToText.",
        },
        {
          title: "FaceTime, Webex, Discord, Slack huddles",
          body:
            "Any app that plays the other people through your Mac works the same way. If you can hear them on the Mac, VoiceToText can record them, along with your microphone.",
        },
        {
          title: "Headphones and AirPods",
          body:
            "Listening on headphones is fine. The other side of the call is taken from macOS as system audio rather than picked up by your microphone from the speakers, so it’s recorded either way.",
        },
        {
          title: "In the same room",
          body: (
            <>
              With no call, the microphone records the room. Keep the Mac close to the people talking, or pick
              an external microphone in Settings → General → Microphone. For a meeting that half the people
              join remotely, both the room mic and the call audio are recorded.
            </>
          ),
        },
      ],
    },
    {
      id: "how-it-hears",
      eyebrow: "How it works",
      title: "Your microphone and the Mac’s sound, recorded together on the Mac.",
      paragraphs: [
        <>
          VoiceToText asks macOS for two audio sources through ScreenCaptureKit, Apple’s capture framework:
          your microphone, and the system audio every app plays. It mixes them into one recording and writes it
          to disk as you go, so an hour-long call never has to fit in memory.
        </>,
        <>
          macOS puts system audio under the same permission as screen recording, listed in System Settings →
          Privacy &amp; Security → Screen &amp; System Audio Recording, so that is what the app asks for the first
          time, along with Microphone. VoiceToText records only the audio, never the screen, and it leaves out
          its own sounds, such as playing back an earlier recording.
        </>,
        <>
          Because it records everything the Mac plays, a notification chime or a video in another tab ends up
          in the recording too. Silence what you don’t want in the transcript before the call starts.
        </>,
        <>
          Your voice comes from the microphone you choose in the app. {MICROPHONE_SETTING}
        </>,
      ],
      note: (
        <>
          There is no live transcript. The text is made after you press Stop &amp; Transcribe, and recordings
          over 12 minutes are transcribed in parts of about 10 minutes, with progress shown. The{" "}
          <Link href="/meeting-recording">meeting recording guide</Link> covers summaries, action items and
          speaker names.
        </>
      ),
    },
    {
      id: "steps",
      eyebrow: "Step by step",
      title: "Record your next call in five steps.",
      cards: [
        {
          title: "Install and open VoiceToText",
          body: `Download the DMG, drag the app to Applications and open it. It runs on ${APP_REQUIREMENTS.os}, on ${APP_REQUIREMENTS.processor} Macs. The default ${DEFAULT_MODEL.name} model downloads once, then transcribes on your Mac.`,
        },
        {
          title: "Check the transcription model",
          body: `In Settings → Conversations, Transcription model is “Same as dictation” by default, which keeps on-device ${DEFAULT_MODEL.name}. Pick ${DIARIZE_MODEL.name} instead only if you want speaker labels and accept sending the audio to OpenAI.`,
        },
        {
          title: "Start just before the call",
          body:
            "Click Start Recording in Conversations, choose Start Conversation Recording from the menu bar, or press your Conversation shortcut (set one in Settings → Shortcut). The first time, turn VoiceToText on in System Settings → Privacy & Security → Screen & System Audio Recording, then start again.",
        },
        {
          title: "Join and talk as usual",
          body:
            "Join from Zoom, Meet, Teams or any other app. The Recording HUD at the top of the screen shows the clock, a level meter and Stop & Transcribe. Drag it aside, or set it to Small, Medium, Large or Off in Settings → Conversations.",
        },
        {
          title: "Stop & Transcribe",
          body:
            "When the call ends, press Stop & Transcribe on the HUD or in Conversations, or press your shortcut again. The transcript lands in Conversations and History with the audio, ready to copy, search, summarize or regenerate.",
        },
      ],
    },
    {
      id: "privacy",
      eyebrow: "Privacy boundary",
      title: "What stays on your Mac, what can leave it, and who is told.",
      paragraphs: [
        <>
          With the default {DEFAULT_MODEL.name} model, or any local Whisper model, the recording is transcribed
          on your Mac and the audio never leaves it. Recordings and transcripts are saved in{" "}
          <code>~/Library/Application Support/VoiceToText/History</code>, and conversations stay there until you
          delete them.
        </>,
        <>
          Audio leaves the Mac only when a cloud model transcribes it, and then it goes directly to that
          provider under your own API key; VoiceToText has no server in the path. Summaries, action items and
          custom prompts send the transcript text, not the audio, to OpenAI, and only when you ask for one.
        </>,
        <>
          Nothing joins the call and VoiceToText sends no notice, so the other people are not told that you are
          recording. If you share your screen, they may see the floating Recording HUD: the app asks macOS to
          keep it out of screen shares, but macOS doesn’t always do so.
        </>,
      ],
      note: (
        <>
          <strong>Ask before you record.</strong> Recording laws differ between countries and states, and some
          require everyone’s consent. Since the app tells no one, it is up to you to say you are recording and
          to follow your workplace’s rules.
        </>
      ),
    },
    {
      id: "tradeoffs",
      eyebrow: "Honest tradeoffs",
      title: "What a meeting bot can do that on-Mac recording can’t.",
      cards: [
        {
          title: "Meetings you can’t attend",
          body:
            "A bot can join a meeting without you. VoiceToText records only what your Mac plays, so your Mac has to be in the call.",
        },
        {
          title: "Names from the meeting",
          body: `A bot inside the call can often take speaker names from the meeting itself. VoiceToText hears one mixed recording: local models return one unlabeled transcript, and only ${DIARIZE_MODEL.name} labels Speaker 1, Speaker 2 and so on, for you to rename.`,
        },
        {
          title: "Notes during the call",
          body:
            "There is no live transcript and no notepad; the text arrives after you stop. There is no calendar or meeting detection either, so you start and stop recording yourself.",
        },
        {
          title: "Only on a Mac",
          body: `VoiceToText runs on ${APP_REQUIREMENTS.os}. There is no Windows, iPhone or web version, so the call has to be on your Mac.`,
        },
      ],
    },
  ],
  comparison: {
    title: "A meeting bot vs. recording on your Mac.",
    caption: "How the two approaches differ in general; individual bot services vary.",
    rowHeader: "Question",
    columns: ["Meeting bot", "VoiceToText on your Mac"],
    rows: [
      {
        label: "How it hears the call",
        cells: [
          "Joins the meeting as a participant.",
          "Captures your microphone and the Mac’s system audio. Nothing joins.",
        ],
      },
      {
        label: "What others see in the call",
        cells: [
          "An extra name in the participant list.",
          "Nothing. If you share your screen, possibly the Recording HUD.",
        ],
      },
      {
        label: "Where the audio is processed",
        cells: [
          "On the bot service’s servers.",
          "On your Mac by default; at a cloud provider only if you choose a cloud model.",
        ],
      },
      {
        label: "Setup",
        cells: [
          "Usually an account and access to your calendar or meeting links.",
          "Install the app and allow Microphone and Screen Recording. No account.",
        ],
      },
      {
        label: "Meetings you don’t attend",
        cells: ["Can usually join without you.", "Records only while your Mac is in the call."],
      },
      {
        label: "Speaker names",
        cells: [
          "Often taken from the meeting’s participant list.",
          `Speaker 1, Speaker 2… with ${DIARIZE_MODEL.name}, renamed by you. None with local models.`,
        ],
      },
      {
        label: "Works with",
        cells: ["The meeting platforms the service supports.", "Any app that plays sound on the Mac."],
      },
      {
        label: "Cost",
        cells: ["Set by the service.", "Free. Optional cloud features are billed to your own API key."],
      },
    ],
    note:
      "A host can remove a bot like any other participant. On-Mac capture can’t be removed from the call because it was never in it, which is exactly why asking for consent is up to you.",
  },
  faqTitle: "Recording calls without a bot: common questions.",
  faq: [
    {
      question: "Can I record a Zoom call on my Mac without a bot joining?",
      answer:
        "Yes. VoiceToText records your microphone and the Mac's system audio, so it captures the whole Zoom call, in the Zoom app or in a browser, without adding anyone to the meeting. It doesn't use Zoom's own recording and installs nothing in Zoom. The transcript is made on your Mac by default when you press Stop & Transcribe.",
    },
    {
      question: "Does it work with Google Meet without a Chrome extension?",
      answer:
        "Yes. Google Meet runs in a browser tab, and VoiceToText records the sound the browser plays like any other app's, in Chrome, Safari or another browser. Nothing is installed in the browser. Mute other tabs that play sound, because everything the Mac plays is recorded.",
    },
    {
      question: "Can I record a Microsoft Teams meeting if I'm not the host?",
      answer:
        "VoiceToText works the same whether you host or join, because it records what your Mac plays instead of using Teams' recording. Whether you may record is a separate question: tell the other people, and check your organization's policy and the law where you and they are.",
    },
    {
      question: "Will the other participants know I'm recording?",
      answer:
        "Not from VoiceToText. Nothing joins the call and the app sends no notice. If you share your screen, they may see the Recording HUD, which macOS doesn't always keep out of a share. Since nobody is told automatically, tell them yourself; some places require everyone's consent to record a call.",
    },
    {
      question: "Does it work with headphones or AirPods?",
      answer:
        "Yes. The other people's voices are taken from macOS as system audio, not picked up by your microphone from the speakers, so they're recorded whether you listen on speakers or headphones. Your own voice comes from the microphone set in Settings → General → Microphone.",
    },
    {
      question: "Does it record video or my screen?",
      answer:
        "No. VoiceToText records only the audio, never the screen. macOS puts system audio under the same permission as screen recording (Screen & System Audio Recording in System Settings → Privacy & Security), which is why the app asks for it.",
    },
    {
      question: "Can it tell who said what?",
      answer: `Only with the optional cloud model ${DIARIZE_MODEL.name}, which needs your OpenAI API key and sends the audio to OpenAI at a list price of ${pricePerHour(DIARIZE_MODEL)}. It labels Speaker 1, Speaker 2 and so on, and Name speakers replaces the labels with names. Local models give one transcript without speaker labels.`,
    },
    {
      question: "Is it free?",
      answer:
        "Yes. Recording and on-device transcription are free, with no account and no limit on minutes. Cloud transcription, speaker labels and AI summaries are optional, and the provider bills them to your own API key.",
    },
  ],
  sources: [
    {
      label: "VoiceToText: MeetingRecorder.swift",
      href: `${REPO_URL}/blob/main/VoiceToText/VoiceToText/Meetings/MeetingRecorder.swift`,
      detail:
        "The capture code: ScreenCaptureKit system audio plus the chosen microphone, mixed into one file written to disk as you record, with the app’s own sound left out.",
    },
    {
      label: "Apple Developer: ScreenCaptureKit",
      href: "https://developer.apple.com/documentation/screencapturekit",
      detail: "Apple’s framework for capturing screen content and audio on macOS. VoiceToText uses it for audio only.",
    },
    {
      label: "Apple Support: Control access to screen and system audio recording on Mac",
      href: "https://support.apple.com/guide/mac-help/control-access-screen-system-audio-recording-mchld6aa7d23/mac",
      detail:
        "Apple’s guide to System Settings → Privacy & Security → Screen & System Audio Recording, where you turn an app’s ability to record on or off.",
    },
    {
      label: "VoiceToText source repository",
      href: REPO_URL,
      detail: "The app’s public source, releases and issue history, for every VoiceToText claim on this page.",
    },
  ],
  related: [
    {
      href: "/meeting-recording",
      title: "Record and transcribe meetings",
      description: "The full Conversations guide: speaker labels, summaries, action items, file import and History.",
    },
    {
      href: "/free-meeting-recorder-mac",
      title: "Free meeting recorder for Mac",
      description: "What costs nothing, what can cost money, and who sends the bill.",
    },
    {
      href: "/granola-alternative",
      title: "VoiceToText vs Granola",
      description: "Another bot-free meeting app, compared on price, data path and features.",
    },
  ],
  ctaTitle: "Record your next call without adding anyone to it.",
  ctaBody:
    "Download VoiceToText, allow Microphone and Screen Recording, and press Start Recording before you join. The transcript is made on your Mac when you stop.",
  analyticsPlacement: "no_bot_meeting",
};

/* ---------- /free-meeting-recorder-mac ---------- */

export const freeMeetingRecorderConfig: SeoLandingConfig = {
  path: "/free-meeting-recorder-mac",
  parent: { name: "Meeting recording", path: "/meeting-recording" },
  title: "Free AI Meeting Recorder for Mac: No Account, No Caps",
  description:
    "What’s free in VoiceToText’s Mac meeting recorder (recording, on-device transcripts, search) and what costs money. No account, trial or minute cap.",
  breadcrumb: "Free meeting recorder",
  eyebrow: "Pricing, plainly",
  readingTime: "7 min",
  h1: "A free meeting recorder for Mac, with no account, no trial and no minute cap.",
  lead:
    "Recording meetings, transcribing them on your Mac and keeping a searchable history cost nothing in VoiceToText, however many hours you record. The only things that can cost money are optional cloud features, and the provider bills those to your own API key, never VoiceToText.",
  heroPoints: ["No paid tier", "No account or sign-up", "No minute cap or trial", "Cloud extras on your own key"],
  summaryTitle: "The short answer",
  summary: (
    <>
      VoiceToText is free. There is no paid plan, no account, no trial period and no limit on minutes or
      meetings. Recording your microphone and the call’s audio, transcribing with any of the {LOCAL.length} local
      models, importing files and searching your history are all included. Three things can cost money, all
      optional: cloud transcription models ({formatPrice(CHEAPEST_CLOUD)} to {formatPrice(PRICIEST_CLOUD)} at
      list price), speaker labels with {DIARIZE_MODEL.name} ({pricePerHour(DIARIZE_MODEL)}), and AI summaries or
      action items, which OpenAI bills per use. You pay the provider on your own API key; VoiceToText never
      charges you.
    </>
  ),
  atAGlance: {
    title: "What’s free, and what can cost money.",
    caption:
      "VoiceToText’s features and the optional cloud ones. Cloud prices are the providers’ list prices as the app’s Models pane shows them.",
    rowHeader: "Feature",
    columns: ["Cost", "Runs on"],
    rows: [
      { label: "Recording your mic and the call", cells: ["Free, no time limit", "Your Mac"] },
      {
        label: "Transcription with a local model",
        cells: ["Free", "Your Mac, offline once the model has downloaded"],
      },
      { label: "History, search, playback and copy", cells: ["Free", "Your Mac"] },
      { label: "Importing an audio or video file", cells: ["Free with a local model", "Your Mac"] },
      {
        label: "Cloud transcription",
        cells: [
          `${formatPrice(CHEAPEST_CLOUD)} to ${formatPrice(PRICIEST_CLOUD)}`,
          `${MEETING_PROVIDERS_OR}, on your own key`,
        ],
      },
      { label: "Speaker labels", cells: [formatPrice(DIARIZE_MODEL), "OpenAI, on your own key"] },
      {
        label: "Summary, action items, custom prompts",
        cells: ["OpenAI’s token rates, per run", "OpenAI, on your own key (text only)"],
      },
    ],
  },
  sections: [
    {
      id: "free",
      eyebrow: "Free, with no limit",
      title: "Everything you need to record and transcribe a meeting costs nothing.",
      cards: [
        {
          title: "Recording",
          body:
            "Your microphone and the Mac’s system audio, mixed into one recording, from Zoom, Google Meet, Teams, FaceTime or any app that plays sound. No bot joins, and nothing limits how long or how often you record.",
        },
        {
          title: "On-device transcription",
          body: `${countWord(LOCAL.length)} local models: ${DEFAULT_MODEL.name}, the default, covers ${DEFAULT_MODEL.languagesInApp}, and ${countWord(LOCAL_WHISPER.length).toLowerCase()} Whisper sizes cover 99 languages. They run on your Mac and work with the network off once downloaded.`,
        },
        {
          title: "History and search",
          body:
            "Every conversation is saved on your Mac with its audio and transcript and stays until you delete it. Search finds words across transcripts, summaries, action items and speaker names.",
        },
        {
          title: "File import",
          body:
            "Drag in one audio or video file at a time (MP3, M4A, WAV, MP4, MOV and other formats macOS reads), and it is transcribed like a recording. Your original file is left untouched.",
        },
        {
          title: "Re-transcribe and compare",
          body:
            "Run a recording again with another model and keep both transcripts side by side. With a local model, that costs nothing too.",
        },
        {
          title: "Long calls",
          body:
            "Recordings over 12 minutes are transcribed in parts of about 10 minutes. With a local model, memory use stays flat however long the call ran.",
        },
      ],
    },
    {
      id: "costs",
      eyebrow: "Optional, on your own key",
      title: "What can cost money, and who sends the bill.",
      intro:
        "VoiceToText has no payment system. When a feature needs a cloud provider, you add your own API key in the app’s Cloud pane, and that provider bills your account at its own list price.",
      paragraphs: [
        <>
          <strong>Cloud transcription.</strong> For a difficult recording, you can transcribe a conversation with
          a cloud model instead of a local one. The cloud models that work for conversations, at the list price
          the app shows, cheapest first, are {joinNames(CLOUD_BY_PRICE.map(cloudModelLabel))}. The audio goes directly
          from your Mac to that provider.
        </>,
        <>
          <strong>Speaker labels.</strong> Only {DIARIZE_MODEL.name} labels who said what (Speaker 1, Speaker 2
          and so on), at {pricePerHour(DIARIZE_MODEL)} of audio. At that rate a 30-minute call costs about{" "}
          {DIARIZE_HALF_HOUR}. Local models are free but return one transcript without labels.
        </>,
        <>
          <strong>Summaries, action items and custom prompts.</strong> These run on OpenAI’s {AI_TEXT_MODEL}{" "}
          and send the transcript text, not the audio. OpenAI bills each run at its token rates, so a longer
          transcript costs more. There is no free built-in AI model for them.
        </>,
      ],
      note: (
        <>
          Want a summary without a key? Copy the transcript from History and paste it into an AI assistant you
          already use. The transcript itself is free; the assistant’s own terms apply to what you paste.
        </>
      ),
    },
    {
      id: "no-account",
      eyebrow: "No account, no caps",
      title: "No sign-up, no trial clock, and no monthly minutes.",
      paragraphs: [
        <>
          There is nothing to sign up for. VoiceToText has no accounts and no server of its own: you download
          the app, allow Microphone and Screen Recording, and record. There is no trial that runs out and no
          feature that unlocks after paying.
        </>,
        <>
          Nothing meters your minutes either. The practical limit is disk space: a conversation is saved as
          16 kHz mono audio, about {STORAGE_MB_PER_HOUR} MB per hour, and stays in History until you delete it.
        </>,
        <>
          The app’s source is available on GitHub, so you can read how recording, transcription and storage
          work instead of taking a pricing page’s word for it.
        </>,
      ],
      note: (
        <>
          Updates are free too. The app checks GitHub Releases and offers Install Update, Later or Skip This
          Version, so nothing installs without you.
        </>
      ),
    },
    {
      id: "pricing-models",
      eyebrow: "How pricing usually works",
      title: "Four ways meeting recorders charge, and what to check.",
      intro:
        "Whatever you use, read the plan details for these points before your recordings depend on it.",
      cards: [
        {
          title: "Monthly minute caps",
          body:
            "Apps with a monthly allowance of transcription minutes or meetings. Check what happens when you run out: whether recording stops, transcription waits, or you are asked to upgrade.",
        },
        {
          title: "Free plans with short history",
          body:
            "Apps whose free plan keeps only recent meetings. Check how long recordings stay, and whether older ones can be saved before they go.",
        },
        {
          title: "Per-seat subscriptions",
          body:
            "Plans billed per user per month. Check whether solo use needs a paid seat, and what happens to your recordings if you cancel.",
        },
        {
          title: "Free app, your own key",
          body:
            "VoiceToText’s model. Recording and local transcription are free with no cap. Cloud features bill your provider account directly, per hour of audio or per run, with nothing added by VoiceToText.",
        },
      ],
    },
    {
      id: "limits",
      eyebrow: "What free doesn’t include",
      title: "Know the gaps before you rely on it.",
      cards: [
        {
          title: "No live transcript",
          body: "The text is made after you press Stop & Transcribe, not during the call. Recording can’t be paused.",
        },
        {
          title: "No meeting detection or calendar",
          body: "VoiceToText doesn’t know when a meeting starts. You start and stop recording yourself.",
        },
        {
          title: "No export files",
          body: "Getting text out means copying it; action items copy as a Markdown checklist. There is no sharing or team workspace.",
        },
        {
          title: "Summaries need an OpenAI key",
          body: "There is no free built-in or local AI model for summaries and action items.",
        },
        {
          title: "Speaker labels are cloud-only",
          body: `Only ${DIARIZE_MODEL.name} separates speakers, and it sends the audio to OpenAI.`,
        },
        {
          title: "Mac only",
          body: `It needs ${APP_REQUIREMENTS.os} on ${APP_REQUIREMENTS.processor}. There is no Windows, iPhone or web version.`,
        },
      ],
      note: (
        <>
          Recording a specific call app? See{" "}
          <Link href="/record-meetings-without-a-bot-mac">how it works in Zoom, Google Meet and Teams</Link>.
        </>
      ),
    },
  ],
  faqTitle: "Free meeting recording on Mac: common questions.",
  faq: [
    {
      question: "Is VoiceToText really free for recording meetings?",
      answer:
        "Yes. There is no paid tier, no subscription and no trial: recording your mic and the call's audio, transcribing with a local model, file import, History and search are all free, with no limit on minutes. The source is available on GitHub. Only optional cloud features cost money, and the provider bills those to your own API key.",
    },
    {
      question: "Do I need an account to use it?",
      answer:
        "No. VoiceToText has no accounts and no server of its own. Download the app, allow Microphone and Screen Recording, and record. An API key is needed only for an optional cloud feature, and it is your own key with that provider.",
    },
    {
      question: "Is there a limit on how long or how often I can record?",
      answer: `No. VoiceToText doesn't meter minutes or meetings. The practical limit is disk space: a conversation is saved as 16 kHz mono audio, about ${STORAGE_MB_PER_HOUR} MB per hour, and stays in History until you delete it.`,
    },
    {
      question: "How much do speaker labels cost?",
      answer: `Speaker labels come only from ${DIARIZE_MODEL.name}, which sends the audio to OpenAI at a list price of ${pricePerHour(DIARIZE_MODEL)} of audio, billed to your OpenAI key. A 30-minute call costs about ${DIARIZE_HALF_HOUR} at that rate. Local models are free but don't label speakers.`,
    },
    {
      question: "What do cloud transcription models cost?",
      answer: `From ${pricePerHour(CHEAPEST_CLOUD)} to ${pricePerHour(PRICIEST_CLOUD)} at the providers' list prices, billed to your own key: ${joinNames(CLOUD_BY_PRICE.map(cloudModelLabel))}. Local models cost nothing.`,
    },
    {
      question: "Can I get AI meeting summaries for free?",
      answer: `Not inside VoiceToText. Summary, Action Items and custom prompts run on OpenAI's ${AI_TEXT_MODEL} with your own OpenAI key, and OpenAI bills each run at its token rates. The transcript itself is free, so you can also copy it into an AI assistant you already use, under that assistant's terms.`,
    },
    {
      question: "Does it work on Apple Silicon and Intel Macs?",
      answer: `Yes. It needs ${APP_REQUIREMENTS.os} on ${APP_REQUIREMENTS.processor}. Local models run much faster on Apple Silicon than on Intel.`,
    },
    {
      question: "Do my recordings go to VoiceToText's developer?",
      answer:
        "No. VoiceToText has no server, account system or in-app analytics, so recordings and transcripts never reach the developer. With a local model they stay on your Mac; with a cloud model the audio goes directly to that provider under your key.",
    },
  ],
  sources: [
    {
      label: "VoiceToText: ModelRegistry.swift",
      href: `${REPO_URL}/blob/main/VoiceToText/VoiceToText/Engine/ModelRegistry.swift`,
      detail: "The model catalog the app ships, with each cloud model’s per-hour list price as the Models pane shows it.",
    },
    {
      label: "VoiceToText source repository",
      href: REPO_URL,
      detail: "The app’s public source, for every claim on this page about what is free and where audio goes.",
    },
    {
      label: "VoiceToText releases",
      href: RELEASES_URL,
      detail: "Free, signed downloads and the full version history.",
    },
  ],
  related: [
    {
      href: "/meeting-recording",
      title: "Record and transcribe meetings",
      description: "How Conversations records, transcribes, labels speakers and writes summaries.",
    },
    {
      href: "/record-meetings-without-a-bot-mac",
      title: "Record calls without a bot",
      description: "Zoom, Google Meet and Teams, app by app, and a meeting bot compared with on-Mac capture.",
    },
    {
      href: "/offline-speech-to-text-mac",
      title: "Offline speech to text on Mac",
      description: "What stays on your Mac with local models, and where the network comes in.",
    },
  ],
  ctaTitle: "Record your next meeting for free.",
  ctaBody:
    "Download VoiceToText, record a call and read the transcript on your Mac. Add an API key later only if you want a cloud feature.",
  analyticsPlacement: "free_meeting_recorder",
};
