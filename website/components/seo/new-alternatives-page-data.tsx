import Link from "next/link";

import {
  APP_VERSION,
  CLOUD_PROVIDERS_OR,
  cloudModels,
  localModels,
  MODEL_CATALOG,
} from "@/lib/app-facts";
import { formatDisplayDate, page, type PagePath } from "@/lib/pages";
import { REGENERATE_MODEL_COUNT } from "@/lib/seo-meeting";

import type { SeoLandingConfig } from "./seo-landing";

// Competitor facts on these two pages come only from the vendor's own pages,
// re-checked on the `sourcesReviewed` date in lib/pages.ts. When you re-check
// them, update the copy and that date together; drop any fact you can no
// longer find on an official page rather than keeping it from memory.

/** The date a page's vendor sources were last re-checked, as display text. */
function sourcesChecked(path: PagePath): string {
  const record = page(path);
  return formatDisplayDate(record.sourcesReviewed ?? record.published);
}

const GRANOLA_CHECKED = sourcesChecked("/granola-alternative");
const MACWHISPER_CHECKED = sourcesChecked("/macwhisper-alternative");
const MODEL_COUNT = MODEL_CATALOG.length;
const LOCAL_COUNT = localModels().length;
const CLOUD_COUNT = cloudModels().length;

export const granolaAlternativeConfig: SeoLandingConfig = {
  path: "/granola-alternative",
  title: "Granola Alternative for Mac: Free, On-Device Transcripts",
  description:
    "Free Mac recorder, no bot, no account: VoiceToText transcribes calls on your Mac. Granola transcribes in the cloud and needs a Google or Microsoft login.",
  breadcrumb: "Granola alternative",
  parent: { name: "Compare", path: "/compare" },
  eyebrow: "Balanced comparison",
  readingTime: "10 min",
  h1: "A Granola alternative that transcribes calls on your Mac.",
  lead:
    "Stay with Granola if you want AI notes built from what you type during the call, calendar prep, templates, team sharing and apps for Windows, iPhone and Android; its Basic plan is free but shows only the last 30 days of notes. Switch to VoiceToText if the audio should be transcribed on your Mac rather than by a cloud provider, or you don’t want an account: it is free and keeps every recording until you delete it. It is Mac-only, with no live notes, calendar or sharing, and it sends text to OpenAI only when you ask for a summary.",
  heroPoints: [
    `Sources checked ${GRANOLA_CHECKED}`,
    "Granola’s wins listed first",
    "Prices from vendor pages",
    "No meeting bot in either app",
  ],
  disclosure: (
    <>
      VoiceToText’s developer wrote this page, so read it as a comparison by an interested party. Every
      Granola fact below comes from Granola’s own website, pricing page, security page or help center, checked
      on {GRANOLA_CHECKED} and linked under <a href="#sources">Sources</a>. This page is not affiliated with
      or endorsed by Granola; the name is used only to identify the product being compared.
    </>
  ),
  summaryTitle: "Which one fits your meetings?",
  summary: (
    <>
      Choose Granola if you take notes during calls and want them turned into AI-written meeting notes, with
      calendar-aware prep, templates, shared folders, voice typing and apps for Windows and phones, and you’re
      fine signing in with Google or Microsoft and having audio go to cloud transcription providers. Choose
      VoiceToText if you want a free Mac app with no account that makes the transcript on your Mac by default,
      keeps every recording in a local history, and treats AI summaries as an optional step you run with your
      own OpenAI key.
    </>
  ),
  atAGlance: {
    title: "At a glance, as of November 2026.",
    caption: `VoiceToText ${APP_VERSION} compared with Granola’s official pages, checked ${GRANOLA_CHECKED}. Plans and features can change.`,
    columns: ["VoiceToText", "Granola"],
    rows: [
      {
        label: "Price",
        cells: [
          "Free. No paid tier.",
          "Basic is free and shows the last 30 days of notes. Business is $14 and Enterprise $35 per user per month.",
        ],
      },
      {
        label: "Account",
        cells: ["None.", "Sign-in with a Google or Microsoft account."],
      },
      {
        label: "How it hears the call",
        cells: [
          "Your mic plus the Mac’s system audio. No bot joins.",
          "Your computer’s mic and system audio on Mac or Windows. No bot joins.",
        ],
      },
      {
        label: "Where speech becomes text",
        cells: [
          "On your Mac by default (Parakeet). Cloud only if you pick a cloud model and add your key.",
          "Cloud transcription providers; Granola names Deepgram and Assembly. Audio isn’t stored.",
        ],
      },
      {
        label: "During the call",
        cells: [
          "A recording clock. The transcript arrives after you stop.",
          "A notepad for your own notes and a live transcript panel.",
        ],
      },
      {
        label: "After the call",
        cells: [
          "Summary, Action Items and up to 3 custom-prompt tabs, run with your OpenAI key.",
          "AI-enhanced notes shaped by templates, plus AI chat within and across meetings.",
        ],
      },
      {
        label: "Calendar and sharing",
        cells: [
          "None. You start and stop recording; copy text to share it.",
          "Google and Microsoft calendars; shared folders and Slack on every plan.",
        ],
      },
      {
        label: "Dictation",
        cells: [
          "⌥Space in any Mac app, with a review step before paste.",
          "Voice typing in any app on Mac, Windows and iOS; Android coming soon.",
        ],
      },
      {
        label: "Platforms",
        cells: ["macOS 15 or later, Apple Silicon or Intel.", "macOS 14 or later, Windows, iOS and Android."],
      },
      {
        label: "Source code",
        cells: ["Public on GitHub, without an open-source license.", "No public source mentioned on its site."],
      },
    ],
  },
  sections: [
    {
      id: "granola-wins",
      eyebrow: "Where Granola wins",
      title: "It is built around the meeting, not just the recording.",
      intro: (
        <>
          Granola is a notepad that fills itself in, and much of its value comes from what happens before and
          during the call.
        </>
      ),
      cards: [
        {
          title: "Notes while you listen",
          body:
            "You write as much or as little as you like in a Granola note while it captures audio, and a transcript panel shows the conversation live. On Mac and Windows, speaker tags, included on every plan, label who said what by display name in Google Meet (through Chrome or Granola’s extension), the Zoom desktop app and Microsoft Teams; elsewhere the transcript splits Me (your mic) from Them (system audio).",
        },
        {
          title: "Calendar and meeting prep",
          body:
            "Granola connects to Google and Microsoft calendars, and its pricing page lists pre-meeting briefs and follow-up emails on the Business plan.",
        },
        {
          title: "Templates and recipes",
          body:
            "Ready-made templates shape notes for common meeting types, such as 1:1s, interviews or sales pitches, and you can write your own. Recipes are saved prompts you run on your notes afterwards. Both are listed on every plan.",
        },
        {
          title: "Teams and every device",
          body:
            "Shared folders, Slack and AI chat are on every plan. Business adds Attio, Notion, HubSpot, Affinity and Zapier integrations, API and MCP access and central billing; Enterprise adds SSO, SCIM and HIPAA-compliant workspaces. There are apps for macOS, Windows, iOS and Android.",
        },
        {
          title: "Voice typing, too",
          body:
            "Granola now includes voice typing for writing with your voice in any app, free on every plan. Its page lists it for Mac, Windows and iOS, with Android coming soon. It doesn’t say where that audio is transcribed.",
        },
      ],
    },
    {
      id: "vtt-case",
      eyebrow: "Where VoiceToText fits",
      title: "A free recorder that keeps the transcript on your Mac by default.",
      intro: (
        <>
          VoiceToText calls meeting recording <strong>Conversations</strong>. The full walkthrough is on the{" "}
          <Link href="/meeting-recording">meeting recording guide</Link>; this is the short version.
        </>
      ),
      cards: [
        {
          title: "No bot, no account",
          body: (
            <>
              It records your microphone and the Mac’s system audio together, so it works with Zoom, Meet, Teams,
              FaceTime, Webex or any app that plays sound. macOS asks for Microphone and Screen Recording
              permission; the app uses the second one for audio only and never records your screen. Start from
              the Conversations pane, the menu bar, or an optional Conversation shortcut.{" "}
              <Link href="/record-meetings-without-a-bot-mac">How it works in Zoom, Meet and Teams</Link>.
            </>
          ),
        },
        {
          title: "Transcribed on your Mac",
          body: (
            <>
              The default model, Parakeet TDT v3, runs on the Mac after a one-time download, so the audio stays
              there. You can set a separate model just for conversations. Only the cloud model GPT-4o Transcribe
              Diarize adds speaker labels, and it sends the audio to OpenAI with your key.{" "}
              <Link href="/offline-speech-to-text-mac">What “offline” covers</Link>.
            </>
          ),
        },
        {
          title: "Summary, action items, your own prompts",
          body:
            "On any recording, one click writes a Summary or an Action Items checklist with task, owner and due date. Owners and dates appear only when someone actually said them. A custom prompt such as “Rewrite this as meeting minutes” adds up to 3 more tabs. These use your OpenAI key and send the transcript text to OpenAI.",
        },
        {
          title: "A history you keep",
          body:
            `Audio and transcripts are saved on your Mac. Search finds words across transcripts, summaries, action items and speaker names. You can regenerate a recording with any of the ${REGENERATE_MODEL_COUNT} models that transcribe recordings and keep each version, or import one audio or video file at a time.`,
        },
      ],
      note: (
        <>
          The same app handles dictation: press ⌥Space in any app, speak, review the text, and paste it. One
          download covers both jobs.
        </>
      ),
    },
    {
      id: "data-path",
      eyebrow: "Privacy and security",
      title: "What stays on your Mac, and what goes to a cloud provider.",
      intro: <>Neither app sends a bot to the call. They differ on where the audio is turned into text.</>,
      paragraphs: [
        <>
          Granola’s security page says it uses cloud processing for transcription and AI summaries. On macOS and
          Windows it transcribes in real time through providers such as Deepgram and Assembly; on a phone, after
          the meeting, from temporarily cached audio. It says it doesn’t store meeting audio, and keeps notes
          encrypted in a US-hosted AWS environment until you delete them. Third parties may not train on your
          data; Granola itself trains on anonymized data unless you opt out in Settings. It lists a SOC 2 Type 2
          report since July 2025, a GDPR data processing agreement on request, and HIPAA-compliant workspaces on
          Enterprise.
        </>,
        <>
          VoiceToText with a local model transcribes on the Mac and saves the audio and text in your user
          folder. There is no VoiceToText server or account. The only network use in that setup is Hugging Face,
          for the one-time model download, and the app’s update check. Once the model has downloaded,
          transcription works with the network off.
        </>,
        <>
          The AI step is where text leaves the Mac. Summary, Action Items and custom prompts send the transcript
          text, including any speaker names you added, to OpenAI with your key. If a conversation must stay on
          the Mac entirely, keep a local model and skip those tabs.
        </>,
      ],
      note:
        "Local doesn’t mean invisible. Recordings stay in your history until you delete them, and anyone using your Mac account can open them. Dictations are the exception: past your latest 200, the oldest are removed automatically unless you starred them or added a summary or action items.",
    },
    {
      id: "give-up",
      eyebrow: "What you give up with VoiceToText",
      title: "Know the gaps before you switch.",
      cards: [
        {
          title: "No live notes during the call",
          body:
            "There is no notepad and no live transcript for conversations. The text appears after you press Stop & Transcribe, and recording can’t be paused.",
        },
        {
          title: "No calendar or meeting detection",
          body:
            "VoiceToText doesn’t know when a meeting starts. You start and stop recording yourself from the app, the menu bar, or your Conversation shortcut.",
        },
        {
          title: "No templates, no cross-meeting chat",
          body:
            "Custom prompts are instructions you type; recent ones are remembered, but there’s no template library. Each insight covers one recording.",
        },
        {
          title: "No sharing or integrations",
          body:
            "No shared folders, team workspace, Slack or Notion. Getting text out means copying it; action items copy as a Markdown checklist. There are no export files.",
        },
        {
          title: "Summaries need your OpenAI key",
          body:
            "There is no built-in or local AI model for summaries. OpenAI bills your account for each run, and speaker labels likewise need an OpenAI cloud model.",
        },
        {
          title: "One Mac, nothing else",
          body:
            "It runs on macOS 15 or later, on Apple Silicon or Intel Macs. There is no Windows or phone app, so in-person meetings need your Mac in the room.",
        },
      ],
    },
    {
      id: "verdict",
      eyebrow: "Verdict by use case",
      title: "Pick by the meetings you actually have.",
      cards: [
        {
          title: "Back-to-back calls with a team → Granola",
          body:
            "Calendar prep, templates, shared folders and integrations save time when meetings are the job and notes are shared.",
        },
        {
          title: "Audio that shouldn’t reach a server → VoiceToText",
          body:
            "Use a local model and skip the AI tabs, and the recording is transcribed and stored only on your Mac.",
        },
        {
          title: "A few calls a week, no budget → VoiceToText",
          body:
            "Recording, transcription and history are free, and conversations stay in History until you delete them; Granola Basic shows only the last 30 days. Add an OpenAI key only if you want summaries.",
        },
        {
          title: "Windows, phones or in-person → Granola",
          body:
            "VoiceToText is a Mac app only. Granola has apps for Windows, iOS and Android, though its phone apps can’t capture audio from virtual meeting apps.",
        },
      ],
      note: (
        <>
          Weighing other apps too? The <Link href="/compare">comparison hub</Link> lists every page, and{" "}
          <Link href="/whisper-vs-parakeet-mac">Whisper vs. Parakeet</Link> explains the local models.
        </>
      ),
    },
  ],
  faq: [
    {
      question: "Is VoiceToText a free Granola alternative?",
      answer:
        "For recording and transcribing meetings on a Mac, yes. VoiceToText is free, with no paid tier and no account. It records your microphone and the call's system audio without a bot and transcribes on your Mac by default. The optional Summary and Action Items use your own OpenAI API key, so OpenAI bills you for that use. It has no calendar, templates or team features.",
    },
    {
      question: "Does VoiceToText show a live transcript during the meeting?",
      answer:
        "No. A conversation is transcribed after you press Stop & Transcribe. Granola shows a live transcript panel during the call. VoiceToText's live-text models are for dictation only.",
    },
    {
      question: "Does either app join the call as a bot?",
      answer:
        "No. Both capture audio on your computer. VoiceToText needs Microphone and Screen Recording permission on macOS. It uses Screen Recording only to capture system audio and never records your screen.",
    },
    {
      question: "Where does my meeting audio go?",
      answer:
        "With VoiceToText's default local model, the audio is transcribed on your Mac and saved in your local history. It leaves the Mac only if you choose a cloud transcription model. Granola's security page says it sends audio to transcription providers such as Deepgram and Assembly and doesn't store the audio.",
    },
    {
      question: "Can VoiceToText connect to my calendar or detect meetings?",
      answer:
        "No. You start recording from the Conversations pane, the menu bar, or an optional Conversation shortcut, and stop it the same way.",
    },
    {
      question: "Can VoiceToText label who said what?",
      answer:
        "Only with the cloud model GPT-4o Transcribe Diarize, which needs your OpenAI key and sends the audio to OpenAI. It labels Speaker 1, Speaker 2 and so on, and you can rename them with Name speakers. Local models produce one unlabeled transcript.",
    },
    {
      question: "Is there a secure Granola alternative that keeps the audio on my Mac?",
      answer:
        "VoiceToText with its default local model transcribes on your Mac and saves recordings in your user folder, with no account and no VoiceToText server. The audio leaves the Mac only if you pick a cloud model. Granola's security page describes cloud transcription through providers such as Deepgram and Assembly, a SOC 2 Type 2 report, and HIPAA-compliant workspaces on Enterprise, so the real question is whether meeting audio may leave your Mac at all.",
    },
    {
      question: "Is Granola available on Mac, iPhone and Windows? Does it have dictation?",
      answer:
        "Yes. Granola lists apps for macOS, Windows, iOS and Android, though its phone apps can't capture audio from virtual meeting apps. Its voice typing, for writing with your voice in any app, is listed for Mac, Windows and iOS, with Android coming soon, and is free on every plan. VoiceToText runs only on a Mac with macOS 15 or later; its dictation works in any Mac app with Option+Space.",
    },
    {
      question: "Is there an open-source Granola alternative?",
      answer:
        "VoiceToText's source code is public on GitHub, so you can read how it records, stores and sends data. The repository has no open-source license, though, so it is source available rather than open source: you can inspect the code, but it doesn't come with rights to modify or redistribute it. We found no statement on Granola's site that its source is public.",
    },
    {
      question: "Is Granola free?",
      answer:
        "Granola Basic is free with unlimited meeting notes, but only the last 30 days of meeting history stay viewable. Business is $14 and Enterprise $35 per user per month, according to Granola's pricing page. VoiceToText is free with no paid tier and keeps conversations until you delete them; only optional summaries and cloud models bill your own provider key.",
    },
  ],
  sources: [
    {
      label: "Granola: Home page",
      href: "https://www.granola.ai/",
      detail:
        "Product positioning as an AI notepad for back-to-back meetings, bot-free capture from computer audio, and the platforms it lists.",
    },
    {
      label: "Granola: Pricing",
      href: "https://www.granola.ai/pricing",
      detail:
        "Basic, Business ($14) and Enterprise ($35) per user per month, the 30-day history limit on Basic, templates, recipes, shared folders, Slack, voice typing, integrations, SSO, SCIM and HIPAA.",
    },
    {
      label: "Granola: Security",
      href: "https://www.granola.ai/security",
      detail:
        "Cloud transcription providers, audio not being stored, US-hosted AWS storage and retention, the model-training policy, SOC 2 Type 2, GDPR and HIPAA.",
    },
    {
      label: "Granola: Voice typing",
      href: "https://www.granola.ai/voice-typing",
      detail: "Voice typing in any app, the platforms it lists (Mac, Windows and iOS, Android coming soon) and that it is free for all users.",
    },
    {
      label: "Granola Help: How transcription works",
      href: "https://docs.granola.ai/help-center/taking-notes/transcription",
      detail:
        "No meeting bot, mic and system audio sent to the transcription provider, the live transcript panel, Me/Them labels, and speaker tags in Google Meet, Zoom and Microsoft Teams.",
    },
    {
      label: "Granola Help: Templates",
      href: "https://docs.granola.ai/help-center/taking-notes/customise-notes-with-templates",
      detail: "Built-in and custom note templates and which apps support them.",
    },
    {
      label: "Granola Help: Setup guide",
      href: "https://docs.granola.ai/help-center/getting-started/setting-up-granola-for-the-first-time",
      detail: "The macOS 14 minimum, sign-in with a Google or Microsoft account only, calendar connection and audio permissions.",
    },
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail: "The app’s source and releases, for every VoiceToText claim on this page.",
    },
  ],
  related: [
    {
      href: "/meeting-recording",
      title: "Record meetings on Mac",
      description: "How Conversations captures mic and system audio, transcribes it, and adds AI summaries and action items.",
    },
    {
      href: "/macwhisper-alternative",
      title: "MacWhisper alternative",
      description: "Compare a file-transcription specialist with a free app built around dictation and meetings.",
    },
    {
      href: "/free-meeting-recorder-mac",
      title: "Free meeting recorder for Mac",
      description: "What VoiceToText records and transcribes for free, and what the optional cloud extras cost per hour.",
    },
  ],
  ctaTitle: "Record your next call and read the transcript on your Mac.",
  ctaBody:
    "Open Conversations and press Start Recording before the call. Add an OpenAI key later only if you want summaries and action items.",
  analyticsPlacement: "granola_alternative",
};

export const macwhisperAlternativeConfig: SeoLandingConfig = {
  path: "/macwhisper-alternative",
  title: "MacWhisper Alternative for Mac: Free, Local, No Account",
  description:
    "VoiceToText is free with no Pro tier or account; MacWhisper Pro is €64 once. Both transcribe on your Mac. Who should switch, plus other alternatives.",
  breadcrumb: "MacWhisper alternative",
  parent: { name: "Compare", path: "/compare" },
  eyebrow: "Balanced comparison",
  readingTime: "9 min",
  h1: "A free MacWhisper alternative for dictation and calls.",
  lead:
    "Stay with MacWhisper if your work starts with recorded files: even its free version exports .srt and .vtt subtitles, and the one-time Pro license adds batch runs, watched folders, speaker recognition and Word, PDF and Markdown exports. Switch to VoiceToText if you mostly talk into apps or record calls: it is free with no Pro tier or account, transcribes on your Mac by default, and includes the meeting recording that MacWhisper lists under Pro. VoiceToText has no subtitles, export files or batch mode, so file-heavy work is still MacWhisper’s job.",
  heroPoints: [
    `Sources checked ${MACWHISPER_CHECKED}`,
    "MacWhisper’s wins listed first",
    "Prices from vendor pages",
    "Both run models on your Mac",
  ],
  disclosure: (
    <>
      VoiceToText’s developer wrote this page, so read it as a comparison by an interested party. Every
      MacWhisper fact below comes from MacWhisper’s website and its official store page, checked on{" "}
      {MACWHISPER_CHECKED} and linked under <a href="#sources">Sources</a>, and so does every fact about the
      other apps named here. This page is not affiliated with or endorsed by MacWhisper or its developer; the
      name is used only to identify the product being compared.
    </>
  ),
  summaryTitle: "Which one should you install?",
  summary: (
    <>
      Choose MacWhisper if your work starts with recorded files: interviews, lectures, podcasts or video that
      need editing, subtitles, many export formats, batch runs or speaker labels on your Mac. Much of that is
      in Pro, a one-time purchase. Choose VoiceToText if you mostly talk into apps and want a review step
      before the text lands, plus free meeting capture with AI summaries on your own OpenAI key. It
      transcribes one file at a time and only copies text out.
    </>
  ),
  atAGlance: {
    title: "At a glance, as of November 2026.",
    caption: `VoiceToText ${APP_VERSION} compared with MacWhisper’s official pages, checked ${MACWHISPER_CHECKED}. Features by tier can change.`,
    columns: ["VoiceToText", "MacWhisper"],
    rows: [
      {
        label: "Price",
        cells: [
          "Free. No paid tier, no account.",
          "Free version. Pro is a one-time license with lifetime updates: €64 on macwhisper.com, €65 at its Gumroad checkout.",
        ],
      },
      {
        label: "Mac requirements",
        cells: [
          "macOS 15 or later. Runs on Intel too, but local models are much faster on Apple Silicon.",
          "macOS 14 or later. Recommends M-series Macs; also runs on Intel. iPhone and iPad apps exist.",
        ],
      },
      {
        label: "Local models",
        cells: [
          "Parakeet TDT v3 (default) and five Whisper sizes (99 languages).",
          "Whisper models, some fully available only in Pro. Pro adds Parakeet v2 and v3, WhisperKit and Qwen3-ASR.",
        ],
      },
      {
        label: "Cloud transcription",
        cells: [
          `${CLOUD_COUNT} optional models from ${CLOUD_PROVIDERS_OR}, on your own key.`,
          "Pro: OpenAI, ElevenLabs, Deepgram, Groq, Gladia or a custom Whisper server.",
        ],
      },
      {
        label: "Files",
        cells: [
          "One audio or video file at a time. No batch.",
          "Drag-and-drop files. Pro adds batch runs, watched folders and YouTube or media links.",
        ],
      },
      {
        label: "Export",
        cells: [
          "Copy to the clipboard only. No subtitles, timestamps or files.",
          "Free: .srt, .vtt and .txt. Pro adds .md, .pdf, .html, .docx and more.",
        ],
      },
      {
        label: "Speaker labels",
        cells: [
          "Only with the cloud model GPT-4o Transcribe Diarize and your OpenAI key.",
          "Pro: on-device speaker recognition on M-series Macs, or through ElevenLabs and Deepgram.",
        ],
      },
      {
        label: "Dictation",
        cells: [
          "⌥Space in any app, a review panel before paste, optional AI actions.",
          "System-wide dictation in the free version; Pro adds grammar fixes and AI prompts.",
        ],
      },
      {
        label: "Meetings",
        cells: [
          "Mic plus system audio, no bot, free. Summary and Action Items with your OpenAI key.",
          "Pro: auto-records Zoom, Teams, Webex and other meeting apps, with start and end detection.",
        ],
      },
    ],
  },
  sections: [
    {
      id: "macwhisper-wins",
      eyebrow: "Where MacWhisper wins",
      title: "It is the deeper tool for working with recorded files.",
      intro: (
        <>
          If transcripts are something you edit, publish or hand to someone else, MacWhisper has years of work
          on that path. VoiceToText doesn’t try to match it.
        </>
      ),
      cards: [
        {
          title: "Exports and subtitles",
          body:
            "The free version exports .srt and .vtt subtitles and plain text, with timecodes. Pro adds Markdown, PDF, HTML, Word and custom export formats, plus an inline video player that shows subtitles in sync.",
        },
        {
          title: "Batch and automation",
          body:
            "Pro transcribes many files in a row, watches folders for new files, takes YouTube and media links, and forwards transcripts to Notion, Obsidian, Zapier, Make, n8n or a webhook. It also has a command-line interface.",
        },
        {
          title: "Editing and languages",
          body:
            "A built-in editor lets you correct and delete segments, with audio playback synced to the text. It lists 100 languages with a language picker or auto-detect, filler-word removal, and translation in Pro.",
        },
        {
          title: "More models and AI providers",
          body:
            "Pro adds Parakeet, WhisperKit and Qwen3-ASR models, speaker recognition on the Mac, cloud transcription through several providers, and AI prompts through OpenAI, Anthropic, Google, Groq, xAI, local Ollama or LM Studio, and others.",
        },
      ],
      note:
        "MacWhisper’s store page lists macOS 14 or later and says it also runs on Intel Macs. Some features, such as Parakeet, need an M-series Mac and Qwen3-ASR needs macOS 26.",
    },
    {
      id: "vtt-case",
      eyebrow: "Where VoiceToText fits",
      title: "Built for talking into apps, with meetings and files alongside.",
      cards: [
        {
          title: "Dictation with a review step",
          body:
            "Press ⌥Space in any app, speak, and press it again. The text opens in a review panel: Return pastes it, ⌘R records another take at the caret, and optional AI actions such as Fix grammar run with ⌘1–⌘9 and your OpenAI key. Turn review off to paste straight away.",
        },
        {
          title: "Everything included, for free",
          body: (
            <>
              There’s no Pro tier. All {MODEL_COUNT} models are available: {LOCAL_COUNT} run on the Mac, and{" "}
              {CLOUD_COUNT} cloud models work with your own {CLOUD_PROVIDERS_OR} key. Parakeet TDT v3 is the
              default. <Link href="/whisper-vs-parakeet-mac">Whisper vs. Parakeet</Link> explains the local
              choice.
            </>
          ),
        },
        {
          title: "Meetings with summaries",
          body: (
            <>
              Record your mic and the call’s audio without a bot, transcribe on the Mac, then add a Summary,
              an Action Items checklist or custom-prompt tabs with your OpenAI key. See{" "}
              <Link href="/meeting-recording">meeting recording on Mac</Link>.
            </>
          ),
        },
        {
          title: "One searchable history",
          body:
            "Dictations, recorded calls and imported files land in one local history. Search covers transcripts, summaries, action items and speaker names, and you can re-transcribe any recording with another model while keeping each version.",
        },
      ],
    },
    {
      id: "other-alternatives",
      eyebrow: "Other MacWhisper alternatives",
      title: "Three more Mac apps to consider.",
      intro: (
        <>
          If what you need is MacWhisper’s file work rather than dictation, these are worth a look too. Each line
          comes from the app’s own site, checked {MACWHISPER_CHECKED}; we haven’t benchmarked any of them.
        </>
      ),
      cards: [
        {
          title: "Aiko",
          body:
            "Sindre Sorhus’s transcriber is a one-time $24 purchase that covers all its platforms, and it needs macOS, iOS or visionOS 26.6 or later. It transcribes audio and video files on the device and exports text, SRT, WebVTT, JSON and CSV, with timestamps.",
        },
        {
          title: "Buzz",
          body:
            "Buzz Classic is free and open source under the MIT license on GitHub. It transcribes and translates audio and video files offline and exports TXT, SRT and VTT. Check its download page for which Macs the current version supports.",
        },
        {
          title: "Superwhisper",
          body: (
            <>
              Mainly a dictation app, on Mac, Windows, iOS and Android, but its Pro plan adds audio and video
              file transcription. Pro is $8.49 a month, $84.99 a year or $249.99 once. See{" "}
              <Link href="/superwhisper-alternative">VoiceToText vs. Superwhisper</Link>.
            </>
          ),
        },
      ],
      note: (
        <>
          For subtitles and exports, Aiko and Buzz are closer to MacWhisper than VoiceToText is. VoiceToText is the
          pick when the same app also has to handle dictation and meetings.
        </>
      ),
    },
    {
      id: "give-up",
      eyebrow: "What you give up with VoiceToText",
      title: "Know the gaps before you switch.",
      cards: [
        {
          title: "No exports, subtitles or timestamps",
          body:
            "Transcripts are plain text you copy to the clipboard. There are no .srt, .vtt, .docx or other files, and no timecodes.",
        },
        {
          title: "One file at a time",
          body:
            "Import one audio or video file per run, from Upload File… or by dragging it onto Conversations. No batch, watched folders or links. History keeps the extracted audio, not the original video.",
        },
        {
          title: "No transcript editor",
          body:
            "You can select and copy text but not edit it inside the app. Playback is play and stop only, with no seeking or speed control.",
        },
        {
          title: "No language picker",
          body: (
            <>
              Local Whisper in VoiceToText covers 99 languages but detects the language itself; there’s no
              picker to pin one. Parakeet covers 25 European languages, also detected automatically.{" "}
              <Link href="/offline-speech-to-text-mac">What runs offline</Link>.
            </>
          ),
        },
        {
          title: "Speaker labels need the cloud",
          body:
            "Only GPT-4o Transcribe Diarize separates speakers, using your OpenAI key and sending the audio to OpenAI. Local models return one unlabeled block.",
        },
        {
          title: "Mac only",
          body:
            "It needs macOS 15 or later, and local models run much slower on Intel Macs than on Apple Silicon. There is no iPhone or iPad app, and AI features use OpenAI only, with no local language model.",
        },
      ],
    },
    {
      id: "verdict",
      eyebrow: "Verdict by use case",
      title: "Pick by what you do most.",
      cards: [
        {
          title: "Subtitles, interviews, podcasts → MacWhisper",
          body:
            "Exports, the editor, batch runs and on-device speaker recognition make it the better file workbench. Plan on Pro for most of that.",
        },
        {
          title: "Dictating into apps all day → VoiceToText",
          body:
            "The review panel, Resume, and AI actions are built for writing messages, documents and prompts by voice, free.",
        },
        {
          title: "Recording calls without paying → VoiceToText",
          body:
            "Meeting capture, local transcription and history are part of the free app. MacWhisper’s plan table lists meeting recording under Pro, and its store page lists system-audio recording as a Pro feature.",
        },
        {
          title: "Non-English audio on the Mac → it depends",
          body:
            "Both stay local. VoiceToText’s local Whisper models cover 99 languages, detected automatically, and Parakeet 25 European ones. MacWhisper lists 100 languages, with a picker or auto-detect.",
        },
      ],
      note: (
        <>
          Both apps can live on the same Mac; give them different shortcuts. For more options, see the{" "}
          <Link href="/compare">comparison hub</Link>.
        </>
      ),
    },
  ],
  faq: [
    {
      question: "Is VoiceToText a free MacWhisper alternative?",
      answer: `For dictation, meeting capture and single-file transcription, yes. VoiceToText is free with no paid tier or account, and all ${MODEL_COUNT} models are available. It doesn't replace MacWhisper for exports, subtitles, batch transcription or transcript editing.`,
    },
    {
      question: "What are the best MacWhisper alternatives?",
      answer:
        "It depends on the job. For file transcription with subtitle exports, Aiko (a one-time $24 purchase) and Buzz Classic (free and open source under MIT) both run on the device. For dictation, meetings and one-file imports in one free app, VoiceToText. Superwhisper covers dictation on more platforms and adds file transcription in its Pro plan. MacWhisper itself has a free version, so try that first if exports matter.",
    },
    {
      question: "Is MacWhisper free?",
      answer:
        "There is a free version that records from your microphone, transcribes files in 100 languages, exports .srt, .vtt and .txt, and includes system-wide dictation. MacWhisper Pro is a one-time license with lifetime updates: €64 on macwhisper.com, €65 at its Gumroad checkout. VoiceToText has no paid tier at all.",
    },
    {
      question: "Can VoiceToText export SRT or VTT subtitles?",
      answer:
        "No. VoiceToText transcripts are plain text without timestamps, and you get them out by copying to the clipboard. MacWhisper exports .srt and .vtt subtitles in its free version.",
    },
    {
      question: "Does VoiceToText use Whisper like MacWhisper?",
      answer:
        "It includes five local Whisper models, from Tiny to Large v3, but the default is NVIDIA's Parakeet TDT v3. In VoiceToText, local Whisper covers 99 languages, detected automatically; Parakeet covers 25 European languages, and cloud models 90 to 99+.",
    },
    {
      question: "Can VoiceToText transcribe several files at once?",
      answer:
        "No. You import one audio or video file at a time with Upload File or by dragging it onto the Conversations pane. It is transcribed with the model you chose for conversations, which runs on your Mac by default.",
    },
    {
      question: "Do both apps work offline?",
      answer:
        "Both can transcribe with models that run on the Mac. In VoiceToText, the default Parakeet model downloads once; after that, dictation, recording and file transcription work without a connection. Its Whisper models work offline the same way. Cloud models, AI actions and AI summaries need the internet and your own API key.",
    },
  ],
  sources: [
    {
      label: "MacWhisper: Home and pricing",
      href: "https://macwhisper.com/",
      detail:
        "The Free and Pro feature table, the one-time Pro price listed there (€64), supported formats, export formats by tier, meeting recording, dictation, AI providers, watched folders, integrations and the CLI.",
    },
    {
      label: "MacWhisper: Official store page",
      href: "https://goodsnooze.gumroad.com/l/macwhisper",
      detail:
        "The full feature list by tier, the €65 Pro license price at checkout, supported macOS versions and hardware, Parakeet and Qwen3-ASR requirements, speaker recognition, cloud transcription providers, batch and watched folders, system-audio recording, and the iPhone and iPad apps.",
    },
    {
      label: "Aiko by Sindre Sorhus",
      href: "https://sindresorhus.com/aiko",
      detail: "The $24 one-time price, OS requirements, on-device transcription, supported files and export formats.",
    },
    {
      label: "Buzz",
      href: "https://buzzcaptions.com/",
      detail: "Buzz Classic as free and open source, offline transcription and translation, and export formats.",
    },
    {
      label: "Buzz on GitHub",
      href: "https://github.com/chidiwilliams/buzz",
      detail: "The MIT license and the project’s README.",
    },
    {
      label: "Superwhisper: Voice to text for Mac",
      href: "https://superwhisper.com/voice-to-text-mac",
      detail: "Platforms, Pro file transcription and the Pro prices.",
    },
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail: "The app’s source and releases, for every VoiceToText claim on this page.",
    },
  ],
  related: [
    {
      href: "/whisper-vs-parakeet-mac",
      title: "Whisper vs. Parakeet",
      description: "Choose between the two local model families VoiceToText runs on your Mac.",
    },
    {
      href: "/granola-alternative",
      title: "Granola alternative",
      description: "Compare an AI meeting notepad with a free recorder that transcribes on your Mac.",
    },
    {
      href: "/compare/best-dictation-apps-for-mac",
      title: "Best dictation apps for Mac",
      description: "Seven Mac dictation apps side by side on dictation, files, meetings, privacy, languages and price.",
    },
  ],
  ctaTitle: "Dictate a paragraph, then drop in a file.",
  ctaBody:
    "Try the review panel with ⌥Space in the app you write in most, then drag one recording onto Conversations and compare the transcript with what you use today.",
  analyticsPlacement: "macwhisper_alternative",
};
