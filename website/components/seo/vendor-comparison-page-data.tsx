import Link from "next/link";

import { CLOUD_PROVIDERS_AND, CLOUD_PROVIDERS_OR, cloudModels } from "@/lib/app-facts";
import { formatDisplayDate, page, type PagePath } from "@/lib/pages";
import { countWord } from "@/lib/seo";

import type { SeoLandingConfig } from "./seo-landing";

/** The date a page's vendor sources were last re-checked, as display text. */
function sourcesChecked(path: PagePath): string {
  const record = page(path);
  return formatDisplayDate(record.sourcesReviewed ?? record.published);
}

const SUPERWHISPER_CHECKED = sourcesChecked("/superwhisper-alternative");
const WISPR_CHECKED = sourcesChecked("/wispr-flow-alternative");

export const superwhisperAlternativeConfig: SeoLandingConfig = {
  path: "/superwhisper-alternative",
  parent: { name: "Compare", path: "/compare" },
  title: "Superwhisper Alternative for Mac: Free, Local, No Account",
  description:
    "VoiceToText is free with no account; Superwhisper Pro is $8.49/month or $249.99 once. Both transcribe on your Mac. Who should switch, plus other options.",
  breadcrumb: "Superwhisper alternative",
  eyebrow: "Balanced comparison",
  readingTime: "8 min",
  h1: "A free Superwhisper alternative for Mac, local-first and inspectable.",
  lead:
    "Stay with Superwhisper if you dictate on Windows, iPhone or Android as well as a Mac, want Super Mode to reshape text for each app, or want Pro’s cloud models and file transcription; its free tier already runs Whisper on your Mac without an account. Switch to VoiceToText if one Mac is enough and you’d rather pay nothing at all: local Parakeet and Whisper, a review step before paste, meeting recording and a searchable history are all free, with the source on GitHub. Superwhisper Pro is $8.49 a month, $84.99 a year or $249.99 once.",
  heroPoints: [
    `Sources checked ${SUPERWHISPER_CHECKED}`,
    "Prices from vendor pages",
    "Both products credited",
    "Local mode vs local mode",
  ],
  summaryTitle: "Which one should you try?",
  summary: (
    <>
      Choose Superwhisper when cross-platform availability, its Super Mode formatting, a broad model catalog
      with cloud options in Pro, and an established commercial product matter. Choose VoiceToText when you want
      a free Mac app with source on GitHub, no account, a review-before-paste flow, and local meeting and file
      transcription with optional AI summaries on your own key. Test both with your language and vocabulary;
      this page does not claim either is more accurate.
    </>
  ),
  disclosure: (
    <>
      This is VoiceToText’s own website, written by its developer. There are no affiliate links or
      sponsorships. Superwhisper facts, and the facts about the other apps named here, come from their official
      pages, checked {SUPERWHISPER_CHECKED} and linked below.
    </>
  ),
  atAGlance: {
    title: "VoiceToText vs Superwhisper at a glance.",
    caption: `Superwhisper as documented on its official site (checked ${SUPERWHISPER_CHECKED}).`,
    columns: ["VoiceToText", "Superwhisper"],
    rows: [
      { label: "Platforms", cells: ["Mac (macOS 15+, Apple Silicon or Intel)", "Mac (macOS 14+), Windows, iOS and Android"] },
      {
        label: "Local transcription",
        cells: ["Yes: Parakeet and 5 Whisper sizes", "Yes: Whisper on the free tier; Pro adds Parakeet, Cohere and more"],
      },
      { label: "AI formatting", cells: ["Opt-in actions in review, on your OpenAI key", "Super Mode and custom modes, built in"] },
      {
        label: "Meetings",
        cells: ["Mic + system audio, no bot; AI summaries on your key", "On the Mac since October 2026: no bot, speaker labels"],
      },
      { label: "Account", cells: ["None", "Not needed to try it or to work offline"] },
      { label: "Source", cells: ["Public on GitHub", "No public source mentioned"] },
      { label: "Price", cells: ["Free, no paid tier", "Free tier; Pro $8.49/month, $84.99/year or $249.99 lifetime"] },
    ],
  },
  sections: [
    {
      id: "superwhisper-case",
      eyebrow: "The case for Superwhisper",
      title: "It covers more platforms and more layers of the writing workflow.",
      paragraphs: [
        <>
          Superwhisper’s site lists apps for Mac, Windows, iOS and Android. On a Mac it puts text at the cursor
          in any app, runs from a global shortcut or push-to-talk, and with a local model transcribes on the
          device, with no audio leaving it. Its Mac page lists macOS 14 or later on Apple Silicon or Intel,
          though the Parakeet and Cohere local models aren’t available on Intel.
        </>,
        <>
          The product’s distinguishing layer is not only speech recognition. Super Mode adapts its output to the
          app or screen you’re in, and preset modes such as Voice, Message and Email, plus custom modes, cover
          different writing styles. That can be valuable for someone who wants spoken drafts cleaned and
          reshaped with less manual review.
        </>,
        <>
          The free tier doesn’t expire and runs Whisper models on your Mac in 100+ languages; you don’t need an
          account or an API key to try it. Pro adds more local models such as Parakeet and Cohere, cloud models
          such as Scribe V2 and Nova 3, your own AI API keys, and file transcription, for $8.49 a month, $84.99
          a year or $249.99 once, with a 30-day refund. Its pages disagree on whether every local Whisper model
          is now free, so check the models page for the one you want.
        </>,
        <>
          Meetings arrived on the Mac in version 3.0.0 on October 15, 2026. It records calls in the background
          with no bot and writes notes and speaker-labeled transcripts with fully offline models; FaceTime calls
          work since 3.1.0. Superwhisper’s homepage lists Meetings on the free plan, while its meetings page says
          it is included in Pro. Version 3.3.0, from November 12, 2026, imports meetings from Granola, Wispr Flow
          and Otter.
        </>,
      ],
    },
    {
      id: "vtt-case",
      eyebrow: "The case for VoiceToText",
      title: "A smaller surface can be a feature when transparency and control come first.",
      cards: [
        {
          title: "Free, with source on GitHub",
          body:
            "The source is public, and there is no paid tier, account or subscription. You can read how audio, permissions, history and paste behavior are implemented.",
        },
        {
          title: "Local by default",
          body: `Parakeet (25 European languages) and five Whisper sizes (99 languages) run on your Mac after the model download. ${countWord(cloudModels().length)} optional cloud models need your own ${CLOUD_PROVIDERS_OR} key.`,
        },
        {
          title: "Review as the core workflow",
          body:
            "Stop dictation, correct the complete transcript in a floating panel, add a take at the caret with ⌘R, and press Return to paste. Opt-in AI actions such as Clean transcript or Improve prompt run on ⌘1–⌘9.",
        },
        {
          title: "Meetings without a bot",
          body: (
            <>
              Record your microphone and the Mac’s system audio, or drop in a file, and transcribe locally.
              Each recording can get an AI summary, an action-item checklist or your own prompt’s result, on
              your OpenAI key. See <Link href="/meeting-recording">meeting recording</Link>.
            </>
          ),
        },
        {
          title: "Search everything you said",
          body:
            "History keeps dictations, meetings and imports on the Mac with their audio. Search covers transcripts, summaries, action items and speaker names, and any recording can be regenerated with another model.",
        },
        {
          title: "Scriptable",
          body:
            "A voicetotext:// URL scheme starts, stops or cancels dictation from Raycast, Shortcuts, Stream Deck or a script.",
        },
      ],
    },
    {
      id: "tradeoffs",
      eyebrow: "Tradeoffs to accept",
      title: "VoiceToText is not a drop-in copy of the broader product.",
      paragraphs: [
        <>
          VoiceToText targets macOS 15 or later on Apple Silicon or Intel Macs. It has no Windows, iOS or Android app and
          no cross-device sync. If you dictate on your phone and your desktop, platform reach may decide the
          comparison immediately.
        </>,
        <>
          VoiceToText’s AI actions are opt-in and manual: you run one per dictation from the review panel,
          and nothing is rewritten automatically. There is no filler-word removal or voice command handling
          unless you run an action. Superwhisper’s marketing emphasizes context-aware cleanup and formatting.
          If you want every utterance reshaped for you, you may prefer that; if you want to see and edit the
          raw result, you may prefer the simpler boundary.
        </>,
        <>
          Public source is valuable for inspection, but visibility alone does not grant permission to modify
          or redistribute, and it is not a support contract or a security certification. Check the
          repository, its maintenance and release cadence, and the support your organization expects.
        </>,
      ],
      note: (
        <>
          Both products offer local transcription. “Superwhisper alternative” here means a different product
          and governance model, not a claim that Superwhisper is cloud-only. For a file-transcription
          specialist, see <Link href="/macwhisper-alternative">VoiceToText vs MacWhisper</Link>; for the
          dictation built into macOS, see{" "}
          <Link href="/apple-dictation-alternative">VoiceToText vs Apple Dictation</Link>.
        </>
      ),
    },
    {
      id: "other-alternatives",
      eyebrow: "Other Superwhisper alternatives",
      title: "Four more Mac dictation apps to consider.",
      intro: (
        <>
          Each line comes from the app’s own site, checked {SUPERWHISPER_CHECKED}. We haven’t benchmarked any of
          them; try two or three with your own voice.
        </>
      ),
      cards: [
        {
          title: "VoiceInk",
          body:
            "A Mac-only dictation app for Apple Silicon, sold as a one-time license: $25 for one Mac, $39 for two or $49 for three, with a free trial. It transcribes on the device, and its optional AI enhancement sends text, not audio, to a cloud model. Its source is on GitHub under GPL v3.",
        },
        {
          title: "Spokenly",
          body:
            "On macOS, Windows, Linux and iPhone. The Local plan is free, on-device and needs no account, and using your own API keys is free too; Local+ is $29 once, and Pro is $12 a month billed yearly or $15 monthly. It uses cloud models by default, with local Whisper and Parakeet available. Closed source.",
        },
        {
          title: "Wispr Flow",
          body: (
            <>
              Free for 2,000 words a week on Mac, Windows, iPhone and Android; Pro is $15 per user per month, or
              $12 billed annually. See <Link href="/wispr-flow-alternative">VoiceToText vs. Wispr Flow</Link> for
              how it handles your audio.
            </>
          ),
        },
        {
          title: "MacWhisper",
          body: (
            <>
              Best known for file transcription, it includes system-wide dictation in its free version; Pro, a
              one-time €64 license on macwhisper.com, adds AI prompts and grammar fixes for dictation. See{" "}
              <Link href="/macwhisper-alternative">VoiceToText vs. MacWhisper</Link>.
            </>
          ),
        },
      ],
      note: (
        <>
          Only need quick dictation? Apple’s built-in Dictation needs no install, and its Keyboard settings show
          whether your speech is processed on the device. See{" "}
          <Link href="/apple-dictation-alternative">VoiceToText vs. Apple Dictation</Link>.
        </>
      ),
    },
    {
      id: "decision",
      eyebrow: "Choose by priority",
      title: "Write down the non-negotiable before comparing transcript output.",
      cards: [
        {
          title: "Pick Superwhisper for reach",
          body:
            "You need clients beyond one Mac, want its context-aware formatting and model catalog, or prefer a commercial product ecosystem.",
        },
        {
          title: "Pick VoiceToText for inspectability",
          body:
            "You want a public repository, no account, no paid tier, an explicit choice of local model, a review step, and meeting transcripts you can search.",
        },
        {
          title: "Compare local mode to local mode",
          body:
            "Don’t compare a small local model in one product with a cloud model in the other and call it a product verdict. Match the privacy and processing mode first.",
        },
        {
          title: "Use a personal test set",
          body: (
            <>
              Dictate the same names, technical terms, accent and sentence lengths into both. Measure
              corrections and total time, not just the first impressive sample. The{" "}
              <Link href="/compare">comparison hub</Link> lists the other apps worth testing.
            </>
          ),
        },
      ],
    },
  ],
  comparison: {
    title: "VoiceToText vs Superwhisper, in detail.",
    caption: `Superwhisper behavior as documented on ${SUPERWHISPER_CHECKED}. Plans, models, and requirements can change.`,
    columns: ["VoiceToText", "Superwhisper"],
    rows: [
      {
        label: "Platforms",
        cells: ["macOS.", "Official site lists Mac, Windows, iOS and Android."],
      },
      {
        label: "Source model",
        cells: [
          "Source is public on GitHub, without an open-source license.",
          "Commercial app with free and paid plans; no public source mentioned.",
        ],
      },
      {
        label: "Local transcription",
        cells: [
          "Parakeet (25 European languages) and five Whisper sizes (99 languages) run on the Mac after download, even with the network off.",
          "Free tier runs Whisper on the device without internet; Pro adds Parakeet, Cohere and other local models.",
        ],
      },
      {
        label: "Cloud transcription",
        cells: [
          `${countWord(cloudModels().length)} optional ${CLOUD_PROVIDERS_AND} models on your own key, including live text and speaker labels.`,
          "Pro includes cloud models such as Scribe V2 and Nova 3, and lets you add your own AI API keys.",
        ],
      },
      {
        label: "Output workflow",
        cells: [
          "Review the complete transcript before paste, or paste instantly; opt-in AI actions on your OpenAI key.",
          "System-wide dictation plus Super Mode, preset and custom modes for AI formatting.",
        ],
      },
      {
        label: "Meetings and files",
        cells: [
          "Records microphone plus system audio and imports audio or video files. Optional AI summaries, action items and custom prompts on your OpenAI key; searchable local history.",
          "Meetings (Mac, since version 3.0.0) records calls on the device with no bot, with speaker-labeled transcripts. File transcription is listed under Pro.",
        ],
      },
      {
        label: "Current Mac requirement",
        cells: [
          "macOS 15+, Apple Silicon or Intel.",
          "macOS 14 or later, Apple Silicon or Intel; the Parakeet and Cohere local models aren’t available on Intel.",
        ],
      },
      {
        label: "Account",
        cells: ["None.", "Not needed to try it or to use it offline."],
      },
      {
        label: "Payment model",
        cells: [
          "Free with no paid tier. Cloud models and AI features bill your own provider key.",
          "Free tier; Pro $8.49/month, $84.99/year or $249.99 lifetime, with a 30-day refund; Enterprise is custom.",
        ],
      },
    ],
    note:
      "Neither column is an accuracy score. Model selection, audio, language, hardware, and formatting settings can change the result more than the product name alone.",
  },
  faq: [
    {
      question: "Is there a free alternative to Superwhisper for Mac?",
      answer:
        "VoiceToText is free with no paid tier or account. It runs Parakeet and Whisper models on your Mac, pastes reviewed text into any app, and records meetings. Superwhisper's own free tier also runs Whisper models on your Mac; Superwhisper covers more platforms and formatting features.",
    },
    {
      question: "How much does Superwhisper cost?",
      answer:
        "Superwhisper has a free tier that doesn't expire. Pro is $8.49 a month, $84.99 a year or $249.99 for a lifetime license, with a 30-day refund, and Enterprise is custom, according to superwhisper.com. VoiceToText has no paid tier.",
    },
    {
      question: "What are the best Superwhisper alternatives?",
      answer:
        "For a free Mac app with local models, review before paste and meeting recording, VoiceToText. VoiceInk is a one-time purchase from $25 that transcribes on the device on Apple Silicon Macs, with its source under GPL v3. Spokenly has a free local plan and runs on more platforms. Wispr Flow has a free weekly word allowance and a $15 Pro plan. MacWhisper adds dictation to a file-transcription app, and Apple Dictation is built into macOS.",
    },
    {
      question: "Do both apps work offline?",
      answer:
        "Yes, with local models. Superwhisper documents on-device models that work without internet. In VoiceToText, Parakeet, the default, works with the network off after a one-time download, and so do its Whisper models.",
    },
    {
      question: "Does Superwhisper record meetings?",
      answer:
        "Yes, on the Mac since version 3.0.0 in October 2026. It records calls with no bot and writes speaker-labeled transcripts with offline models. Its homepage and meetings page disagree on whether Meetings needs Pro. VoiceToText records your mic and the call's system audio for free and transcribes on your Mac by default.",
    },
    {
      question: "Does VoiceToText have AI formatting like Super Mode?",
      answer:
        "Not automatically. VoiceToText has opt-in AI actions, such as Clean transcript, Fix grammar and Improve prompt, that you run per dictation from the review panel. They use your OpenAI key and send the transcript text to OpenAI.",
    },
    {
      question: "Can VoiceToText summarize meetings?",
      answer:
        "Yes, with your OpenAI key. Any recording can get a summary, an action-item checklist or the result of your own prompt. Transcription itself can stay local; only the transcript text goes to OpenAI for the summary.",
    },
  ],
  sources: [
    {
      label: "Superwhisper: Home page",
      href: "https://superwhisper.com/",
      detail: "Platforms, the Free, Pro and Enterprise plans, Pro prices, the free tier’s limits, the trial and the refund policy.",
    },
    {
      label: "Superwhisper: Voice to text for Mac",
      href: "https://superwhisper.com/voice-to-text-mac",
      detail:
        "Mac requirements and Intel limits, cursor insertion, push-to-talk, file transcription in Pro, and no account needed to try it.",
    },
    {
      label: "Superwhisper: Models",
      href: "https://superwhisper.com/models",
      detail: "On-device and cloud models, and which tier each belongs to.",
    },
    {
      label: "Superwhisper: Offline transcription",
      href: "https://superwhisper.com/offline-transcription",
      detail: "Local model downloads, offline operation and no audio leaving the device.",
    },
    {
      label: "Superwhisper: Meeting transcription",
      href: "https://superwhisper.com/meeting-transcription",
      detail: "On-device meeting recording without a bot, speaker labels and the plan it is listed under.",
    },
    {
      label: "Superwhisper: Changelog",
      href: "https://superwhisper.com/changelog",
      detail: "Meetings in 3.0.0, FaceTime in 3.1.0, imports in 3.2.0 and 3.3.0, and the local Whisper pricing change in 2.18.2.",
    },
    {
      label: "VoiceInk",
      href: "https://tryvoiceink.com/",
      detail: "One-time license prices, the free trial, Apple Silicon requirement and on-device transcription.",
    },
    {
      label: "VoiceInk on GitHub",
      href: "https://github.com/Beingpax/VoiceInk",
      detail: "The GPL v3 license and the project’s README.",
    },
    {
      label: "Spokenly",
      href: "https://spokenly.app/",
      detail: "Platforms, the Local, Local+ and Pro plans and their prices, and local and cloud models.",
    },
    {
      label: "Wispr Flow: Pricing",
      href: "https://wisprflow.ai/pricing",
      detail: "The free weekly word allowance, Pro pricing and platforms.",
    },
    {
      label: "Apple: Use Dictation on Mac",
      href: "https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac",
      detail: "Apple’s built-in Dictation and where to see whether it processes speech on the device.",
    },
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail:
        "Public implementation and release documentation for the VoiceToText claims in this comparison.",
    },
  ],
  related: [
    {
      href: "/wispr-flow-alternative",
      title: "VoiceToText vs Wispr Flow",
      description: "A local-first Mac app compared with a cloud dictation service and its privacy controls.",
    },
    {
      href: "/whisper-vs-parakeet-mac",
      title: "Whisper vs. Parakeet",
      description: "Benchmark figures, languages and download sizes for the local models in VoiceToText.",
    },
    {
      href: "/compare/best-dictation-apps-for-mac",
      title: "Best dictation apps for Mac",
      description: "Seven Mac dictation apps side by side on dictation, files, meetings, privacy, languages and price.",
    },
  ],
  ctaTitle: "Compare the workflow, not just the feature list.",
  ctaBody:
    "Use the same paragraph and privacy mode in both apps. Count corrections, review time, and friction across a normal workday.",
  analyticsPlacement: "superwhisper_alternative",
};

export const wisprFlowAlternativeConfig: SeoLandingConfig = {
  path: "/wispr-flow-alternative",
  parent: { name: "Compare", path: "/compare" },
  title: "Wispr Flow Alternative for Mac (2026): Free, Offline",
  description:
    "VoiceToText is free; Wispr Flow has a 2,000-word weekly free plan and $15/user/month Pro. On-device vs cloud transcription, meetings and privacy compared.",
  breadcrumb: "Wispr Flow alternative",
  eyebrow: "Balanced comparison",
  readingTime: "8 min",
  h1: "A Wispr Flow alternative for Mac users who want transcription to run locally.",
  lead:
    "Wispr Flow is a polished cross-platform cloud dictation product with AI editing, a meeting notetaker and team controls. VoiceToText is a free Mac app with source on GitHub: its local models transcribe without sending audio anywhere, and it needs no account.",
  heroPoints: [
    `Wispr docs checked ${WISPR_CHECKED}`,
    "Current pricing",
    "No account needed",
    "Cloud strengths acknowledged",
  ],
  summaryTitle: "The deciding difference",
  summary: (
    <>
      If audio must be transcribed on the Mac, choose VoiceToText with a local model: Wispr’s privacy page says
      “Transcription always happens in the cloud.” If you value Flow’s clients for Windows, iPhone and
      Android, automatic polishing, personalization, Notetaker and managed team controls, its cloud design may
      be an acceptable trade. In Flow, training use and cloud storage are separate settings, so check both
      before dictating sensitive material.
    </>
  ),
  disclosure: (
    <>
      This is VoiceToText’s own website, written by its developer, so we have a stake in the outcome. There
      are no affiliate links or sponsorships. Every Wispr Flow fact comes from Wispr’s official pages, checked{" "}
      {WISPR_CHECKED} and linked below.
    </>
  ),
  atAGlance: {
    title: "VoiceToText vs Wispr Flow",
    caption: `Wispr Flow as documented on its official site and help center (checked ${WISPR_CHECKED}).`,
    columns: ["VoiceToText", "Wispr Flow"],
    rows: [
      {
        label: "Where speech is transcribed",
        cells: ["On your Mac with a local model; cloud only if you pick one", "Wispr’s cloud, always"],
      },
      { label: "Works offline", cells: ["Yes, with the default Parakeet model, after its download", "No"] },
      { label: "Account", cells: ["None", "Required"] },
      {
        label: "Price",
        cells: [
          "Free, no paid tier",
          "Free plan (2,000 words a week); Pro $15/user/month, or $12 billed annually",
        ],
      },
      {
        label: "Platforms",
        cells: ["Mac: macOS 15+, Apple Silicon or Intel", "Mac (macOS 12+, Intel or Apple Silicon), Windows, iPhone, Android"],
      },
      {
        label: "AI editing",
        cells: ["Opt-in actions in the review panel, on your OpenAI key", "Built in: auto punctuation, filler removal, backtrack, styles"],
      },
      {
        label: "Meetings",
        cells: [
          "Records mic + system audio, no bot; AI summaries and action items on your OpenAI key",
          "Notetaker on Mac and Windows, no visible bot; cloud transcripts, speaker names, summaries",
        ],
      },
      { label: "Source", cells: ["Public on GitHub", "Proprietary"] },
    ],
  },
  sections: [
    {
      id: "flow-case",
      eyebrow: "The case for Wispr Flow",
      title: "A cloud service can coordinate features that a single-device app does not attempt.",
      paragraphs: [
        <>
          Wispr’s documentation lists Flow for Mac, Windows, iPhone and Android. Dictation comes with
          automatic punctuation, filler-word removal, backtracking (“let’s meet at 2… actually 3”), a personal
          dictionary, snippets and styles, and Wispr says it covers 100+ languages. The goal is text that is
          ready for its destination without a separate cleanup pass. In September 2026 Wispr also announced
          Canto, its own speech model, which runs in its cloud like the rest of Flow.
        </>,
        <>
          Notetaker, Wispr’s meeting tool, runs on Mac and, since September 15, 2026, on Windows. Wispr says it
          captures audio on your device without joining the call as a visible bot, then provides transcripts
          with speaker names, summaries organized by topic, action items and search across meetings, in 21
          languages. It relies on Wispr’s cloud storage.
        </>,
        <>
          For teams, Wispr documents SAML single sign-on on its Growth and Enterprise plans, SCIM provisioning
          and audit logs on Enterprise, admin-locked settings, HIPAA with a signed BAA, and SOC 2 Type II and
          ISO 27001 materials in its Trust Center. Flow also supports macOS 12 or later, which VoiceToText
          doesn’t. Platform and deployment fit can matter more than where the speech model runs.
        </>,
      ],
    },
    {
      id: "privacy",
      eyebrow: "Read the controls carefully",
      title: "Cloud processing, training use, and server storage are three different questions.",
      paragraphs: [
        <>
          Wispr’s privacy page says transcription always happens in the cloud “to provide the best speed and
          accuracy.” No Flow setting moves recognition onto your device.
        </>,
        <>
          Settings → Data and Privacy then has separate controls. “Improve the model for everyone” decides
          whether your dictation audio, transcripts and edits may be used to train or evaluate models.
          “Dictation Cloud Storage” decides whether dictation data is kept on Wispr’s servers; Scratchpad
          sync, iPhone Notes sync, AI summaries and Notetaker depend on it. On desktop, a local-storage setting
          also lets you keep history normally, delete it after 24 hours, or not store it at all.
        </>,
        <>
          Wispr’s help center says that for zero data retention on dictation, both “Improve the model for
          everyone” and “Dictation Cloud Storage” must be off. That is a meaningful control, and it solves a
          different problem from on-device transcription: the audio is still processed in Wispr’s cloud, then
          not kept. Some organizations are fine with that under a contract; others have a policy that
          recordings may not reach any transcription server.
        </>,
      ],
      note:
        "Wispr split these controls on June 17, 2026, when they were called Privacy Mode and Cloud Sync, and its current help center uses the names above. Check the settings in your own account rather than assuming a screenshot from another device applies.",
    },
    {
      id: "vtt-case",
      eyebrow: "The case for VoiceToText",
      title: "Local-first design reduces the number of parties in the audio path.",
      cards: [
        {
          title: "On-device transcription",
          body:
            "Parakeet (25 European languages) and five Whisper sizes (99 languages) run on your Mac after the model download. VoiceToText runs no server, so there is nowhere for it to send your recording.",
        },
        {
          title: "No account",
          body:
            `Download from GitHub Releases and dictate without signing in. Optional cloud models and AI features use API keys you paste in, billed by ${CLOUD_PROVIDERS_OR}.`,
        },
        {
          title: "Review before paste",
          body:
            "The transcript waits in a panel: fix it, press ⌘R to add another take at the caret, then Return to paste. Opt-in AI actions (Clean transcript, Improve prompt, Fix grammar and more) run on ⌘1–⌘9.",
        },
        {
          title: "Meetings with AI summaries",
          body: (
            <>
              Conversations records your microphone and the Mac’s system audio with no bot, and transcribes
              locally when you stop. Each recording can get a summary, an action-item checklist or your own
              prompt’s result, on your OpenAI key. See <Link href="/meeting-recording">meeting recording</Link>.
            </>
          ),
        },
        {
          title: "A history you can search",
          body:
            "Dictations, meetings and imported files stay on the Mac with their audio. Search covers transcripts, summaries, action items and speaker names; you can regenerate any recording with another model.",
        },
        {
          title: "Inspectable implementation",
          body:
            "The Swift source is public. Users and security teams can review permissions, storage, update checks, model code paths and paste behavior.",
        },
      ],
    },
    {
      id: "tradeoffs",
      eyebrow: "What local-first does not give you",
      title: "Privacy architecture is only one dimension of product fit.",
      paragraphs: [
        <>
          VoiceToText runs on one platform: macOS 15 or later on Apple Silicon or Intel Macs. It has no Windows, iPhone or
          Android app, no team dashboard, no single sign-on, and no cross-device sync.
        </>,
        <>
          Flow polishes every dictation automatically. VoiceToText doesn’t: with a local model you get the
          model’s punctuated transcript, with no filler removal or voice commands, and AI cleanup happens only
          when you run an action on your own OpenAI key. With a local model the text also appears when you
          stop, not as you speak. Live text needs one of the cloud streaming models and the Large recording
          HUD.
        </>,
        <>
          VoiceToText’s speaker labels also come only from a cloud model (GPT-4o Transcribe Diarize), and
          names are yours to type, where Flow’s Notetaker names speakers from calendar and context. VoiceToText
          costs nothing, but local models use disk space and processing power, and there is no commercial
          support agreement.
        </>,
      ],
    },
    {
      id: "decision",
      eyebrow: "Choose by policy and workflow",
      title: "Start with the question your organization can actually answer.",
      cards: [
        {
          title: "Must audio stay on-device?",
          body:
            "Use VoiceToText with a local model. Check Settings → Models and the Conversations transcription model, and skip AI actions and summaries for that session, since they send transcript text to OpenAI.",
        },
        {
          title: "Need cross-platform continuity?",
          body:
            "Flow has the stronger platform story. Decide whether its cloud processing and account fit the data involved.",
        },
        {
          title: "Need managed compliance controls?",
          body:
            "Evaluate Wispr’s current security documentation, agreements, admin controls and Trust Center rather than inferring compliance from a local app.",
        },
        {
          title: "Mostly want meeting notes?",
          body: (
            <>
              Compare Notetaker with VoiceToText’s Conversations, and with a dedicated notetaker; see{" "}
              <Link href="/granola-alternative">VoiceToText vs Granola</Link>. For another local-first
              dictation app, see <Link href="/superwhisper-alternative">VoiceToText vs Superwhisper</Link>, or
              browse <Link href="/compare">every comparison</Link>.
            </>
          ),
        },
      ],
    },
  ],
  comparison: {
    title: "VoiceToText vs Wispr Flow, in detail.",
    caption: `Wispr Flow behavior as documented on ${WISPR_CHECKED}. Confirm current settings and plan details before making a policy decision.`,
    columns: ["VoiceToText", "Wispr Flow"],
    rows: [
      {
        label: "Transcription location",
        cells: [
          `On the Mac with Parakeet or Whisper; optional ${CLOUD_PROVIDERS_OR} models are chosen separately and use your key.`,
          "“Transcription always happens in the cloud,” according to Wispr’s privacy page.",
        ],
      },
      {
        label: "Account",
        cells: [
          "None.",
          "Required: sign in with Google, Apple, Microsoft, organization SSO, or email.",
        ],
      },
      {
        label: "Platforms",
        cells: [
          "macOS 15+, Apple Silicon or Intel.",
          "Mac (macOS 12+, Apple Silicon or Intel), Windows 10/11, iPhone (iOS 18.3+), Android 13–16.",
        ],
      },
      {
        label: "Languages",
        cells: [
          "Parakeet: 25 European languages, automatic. Local Whisper: 99 languages, automatic. Cloud models: 90–99+, detected automatically.",
          "100+ for dictation; Notetaker transcribes 21 languages.",
        ],
      },
      {
        label: "Privacy controls",
        cells: [
          "Pick a local model and audio doesn’t leave the Mac. AI actions and summaries send transcript text to OpenAI on your key.",
          "“Improve the model for everyone” controls training use; “Dictation Cloud Storage” controls server storage. Both off gives zero data retention for dictation.",
        ],
      },
      {
        label: "Output processing",
        cells: [
          "Review before paste or instant paste. Opt-in AI actions on your OpenAI key; no voice commands.",
          "Auto punctuation, filler removal, backtracking, dictionary, snippets and styles.",
        ],
      },
      {
        label: "Meetings and notes",
        cells: [
          "Conversations: mic + system audio, file import, speaker labels via a cloud model, AI summaries, action items and custom prompts, searchable local history.",
          "Notetaker on Mac and Windows: on-device capture without a visible bot, cloud transcripts with speaker names, summaries, action items and cross-meeting search.",
        ],
      },
      {
        label: "Governance",
        cells: [
          "Source is public on GitHub; no commercial support or compliance claim is made here.",
          "Proprietary service. SAML SSO on Growth and Enterprise; SCIM and audit logs on Enterprise; SOC 2 and ISO 27001 materials in its Trust Center.",
        ],
      },
      {
        label: "Price",
        cells: [
          "Free with no paid tier. Cloud models and AI features bill your own provider key.",
          "Free plan with 2,000 words a week; Pro $15/user/month or $12 billed annually; Growth and Enterprise plans for teams.",
        ],
      },
    ],
    note:
      "Zero data retention is not the same as on-device transcription: data can be processed in the cloud and then discarded. Decide which requirement your policy actually sets.",
  },
  faq: [
    {
      question: "Is there a free Wispr Flow alternative for Mac?",
      answer:
        "Yes. VoiceToText is free with no paid tier and no account. It transcribes on your Mac with local models and pastes the text into any app. It runs on Apple Silicon and Intel Macs with macOS 15 or later.",
    },
    {
      question: "Does Wispr Flow work offline?",
      answer:
        "No. Wispr's privacy page says transcription always happens in the cloud. VoiceToText works offline with its default Parakeet model once the model has downloaded.",
    },
    {
      question: "Does VoiceToText have a meeting notetaker like Wispr Flow?",
      answer:
        "It records meetings: Conversations captures your microphone and system audio without a bot and transcribes when you stop. With your OpenAI key, each recording can get a summary, action items or your own prompt's result.",
    },
    {
      question: "Does VoiceToText remove filler words and format text like Flow?",
      answer:
        "Not automatically. You review the transcript before pasting, and you can run an opt-in AI action such as Clean transcript, which removes fillers and handles spoken cues, using your own OpenAI key.",
    },
    {
      question: "Can I use VoiceToText on Windows or iPhone?",
      answer:
        "No. VoiceToText is Mac-only. Wispr Flow has apps for Mac, Windows, iPhone and Android.",
    },
  ],
  sources: [
    {
      label: "Wispr Flow: Privacy",
      href: "https://wisprflow.ai/privacy",
      detail:
        "Vendor overview of data controls, retention, certifications, and the statement that transcription always happens in the cloud.",
    },
    {
      label: "Wispr Flow: Manage data sharing, cloud storage and local history",
      href: "https://docs.wisprflow.ai/articles/9609615338-private-cloud-sync-and-data-sharing-preferences-in-wispr-flow",
      detail:
        "Help-center article describing “Improve the model for everyone,” “Dictation Cloud Storage,” local storage options, the features that need cloud storage, and zero data retention.",
    },
    {
      label: "Wispr Flow: Security and privacy overview",
      href: "https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq",
      detail:
        "Vendor details on SAML SSO, SCIM, audit logs, admin-locked settings, and SOC 2 and ISO 27001 documentation.",
    },
    {
      label: "Wispr Flow: What is Flow?",
      href: "https://docs.wisprflow.ai/articles/2772472373-what-is-flow",
      detail: "Platforms, the account requirement, and the internet requirement for transcription.",
    },
    {
      label: "Wispr Flow: Supported devices and system requirements",
      href: "https://docs.wisprflow.ai/articles/1036674442",
      detail: "Minimum macOS, Windows, iOS and Android versions, and Intel Mac support.",
    },
    {
      label: "Wispr Flow: Pricing",
      href: "https://wisprflow.ai/pricing",
      detail: "Free plan limits and Pro, Growth and Enterprise pricing.",
    },
    {
      label: "Wispr Flow: Notetaker",
      href: "https://wisprflow.ai/notetaker",
      detail: "Notetaker platforms, languages, capture without a visible bot, and its summaries, speaker names and search.",
    },
    {
      label: "Wispr Flow: Features",
      href: "https://wisprflow.ai/features",
      detail: "Dictation features: auto punctuation, filler removal, backtracking, dictionary, snippets, styles and language count.",
    },
    {
      label: "Wispr Flow: What’s new",
      href: "https://wisprflow.ai/whats-new",
      detail: "Dated vendor changelog, including the June 2026 privacy-control split, Notetaker on Windows and the Canto model.",
    },
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail:
        "Public implementation and release documentation for the VoiceToText side of this comparison.",
    },
  ],
  related: [
    {
      href: "/superwhisper-alternative",
      title: "VoiceToText vs Superwhisper",
      description: "Two products that both offer local transcription but differ in platform reach and governance.",
    },
    {
      href: "/meeting-recording",
      title: "Record and transcribe meetings",
      description: "How Conversations records calls without a bot, and what AI summaries and action items do.",
    },
    {
      href: "/compare/best-dictation-apps-for-mac",
      title: "Best dictation apps for Mac",
      description: "Seven Mac dictation apps side by side on dictation, files, meetings, privacy, languages and price.",
    },
  ],
  ctaTitle: "Test the architecture your work requires.",
  ctaBody:
    "If on-device transcription is non-negotiable, let the default Parakeet model download, turn off Wi-Fi, and check the whole VoiceToText workflow yourself.",
  analyticsPlacement: "wispr_alternative",
};
