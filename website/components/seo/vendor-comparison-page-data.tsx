import Link from "next/link";

import { formatDisplayDate, page, type PagePath } from "@/lib/pages";

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
  title: "Superwhisper Alternative for Mac — Free & Local",
  description:
    "Compare VoiceToText and Superwhisper for Mac dictation: local models, platforms, formatting, meetings and files, source access, requirements, and price.",
  breadcrumb: "Superwhisper alternative",
  eyebrow: "Balanced comparison",
  readingTime: "6 min",
  h1: "A Superwhisper alternative for Mac users who prioritize free, inspectable, local-first software.",
  lead:
    "Superwhisper is a mature, cross-platform voice product with local and cloud models, AI formatting, and a wider ecosystem. VoiceToText is a narrower Mac app: free, local by default, with source on GitHub, and built around reviewed paste, meeting recording and a searchable history.",
  heroPoints: [
    "Official vendor sources",
    "No unverifiable prices",
    "Both products credited",
    "Local mode vs local mode",
  ],
  summaryTitle: "Which one should you try?",
  summary: (
    <>
      Choose Superwhisper when cross-platform availability, its Super Mode formatting, a broad model catalog,
      iOS continuity, and an established commercial product matter. Choose VoiceToText when you want a free
      Mac app with source on GitHub, no account, a review-before-paste flow, and local meeting and file
      transcription with optional AI summaries on your own key. Test both with your language and vocabulary;
      this page does not claim either is more accurate.
    </>
  ),
  disclosure: (
    <>
      This is VoiceToText’s own website, written by its developer. There are no affiliate links or
      sponsorships. Superwhisper facts come from its official pages, checked {SUPERWHISPER_CHECKED} and
      linked below.
    </>
  ),
  atAGlance: {
    title: "VoiceToText vs Superwhisper at a glance.",
    caption: `Superwhisper as documented on its official site (checked ${SUPERWHISPER_CHECKED}).`,
    columns: ["VoiceToText", "Superwhisper"],
    rows: [
      { label: "Platforms", cells: ["Mac (Apple Silicon, macOS 15+)", "macOS, Windows, iOS and Android"] },
      { label: "Local transcription", cells: ["Yes: Parakeet and 5 Whisper sizes", "Yes: on-device models"] },
      { label: "AI formatting", cells: ["Opt-in actions in review, on your OpenAI key", "Super Mode and modes, built in"] },
      { label: "Meetings", cells: ["Mic + system audio, no bot; AI summaries on your key", "Records meetings from the device without a bot, with speaker labels"] },
      { label: "Source", cells: ["Public on GitHub", "Proprietary"] },
      { label: "Price", cells: ["Free, no paid tier", "Free tier plus paid plans"] },
    ],
  },
  sections: [
    {
      id: "superwhisper-case",
      eyebrow: "The case for Superwhisper",
      title: "It covers more platforms and more layers of the writing workflow.",
      paragraphs: [
        <>
          Superwhisper’s official site describes system-wide dictation for macOS, Windows, iOS and Android. It can
          place text at the cursor, run with a global shortcut or push-to-talk, transcribe files, and use
          on-device models without an internet connection. Its model catalog also documents optional cloud
          transcription.
        </>,
        <>
          The product’s distinguishing layer is not only speech recognition. Super Mode is presented as
          context-aware formatting that adapts output to the app, while modes and AI tooling support different
          writing styles. That can be valuable for someone who wants spoken drafts cleaned and reshaped with
          less manual review.
        </>,
        <>
          Superwhisper is commercial software with a free tier and paid functionality. Pricing and tier
          contents can change, so this comparison deliberately sends readers to the vendor instead of
          freezing a price in copy. Its July 2026 changelog says current Mac releases require macOS 14 or
          later.
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
          body:
            "Parakeet (25 European languages) and five Whisper sizes (English in VoiceToText) run on Apple Silicon after the model download. Nine optional cloud models need your own OpenAI or ElevenLabs key.",
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
          VoiceToText targets macOS 15 or later on Apple Silicon. It has no Windows, iOS or Android app and
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
          and governance model, not a claim that Superwhisper is cloud-only. For a cloud-only comparison, see{" "}
          <Link href="/wispr-flow-alternative">VoiceToText vs Wispr Flow</Link>; for a file-transcription
          specialist, see <Link href="/macwhisper-alternative">VoiceToText vs MacWhisper</Link>; for the
          dictation built into macOS, see{" "}
          <Link href="/apple-dictation-alternative">VoiceToText vs Apple Dictation</Link>.
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
        cells: ["macOS.", "Official site lists macOS, Windows, iOS and Android."],
      },
      {
        label: "Source model",
        cells: ["Source is public on GitHub.", "Commercial proprietary application."],
      },
      {
        label: "Local transcription",
        cells: [
          "Parakeet (25 European languages) and five Whisper sizes (English in VoiceToText) run on the Mac after download. Parakeet also works with the network off; loading a Whisper model needs a connection.",
          "Official model catalog lists on-device models that work without internet.",
        ],
      },
      {
        label: "Cloud transcription",
        cells: [
          "Nine optional OpenAI and ElevenLabs models on your own key, including live text and speaker labels.",
          "Official catalog lists vendor-proxied cloud models as well as on-device choices.",
        ],
      },
      {
        label: "Output workflow",
        cells: [
          "Review the complete transcript before paste, or paste instantly; opt-in AI actions on your OpenAI key.",
          "System-wide dictation plus modes and AI/context-aware formatting promoted by the vendor.",
        ],
      },
      {
        label: "Meetings and files",
        cells: [
          "Records microphone plus system audio and imports audio or video files. Optional AI summaries, action items and custom prompts on your OpenAI key; searchable local history.",
          "Official site documents file transcription and a Meetings mode that records meeting-app audio on your device without a bot, with speaker labels.",
        ],
      },
      {
        label: "Current Mac requirement",
        cells: [
          "macOS 15+ on Apple Silicon.",
          "Vendor changelog dated July 6, 2026 says macOS 14+; official Mac page also describes Intel support.",
        ],
      },
      {
        label: "Payment model",
        cells: [
          "Free with no paid tier. Cloud models and AI features bill your own provider key.",
          "Free tier plus paid features; verify current plan details with the vendor.",
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
        "VoiceToText is free with no paid tier or account. It runs Parakeet and Whisper models on Apple Silicon Macs, pastes reviewed text into any app, and records meetings. Superwhisper covers more platforms and formatting features.",
    },
    {
      question: "Do both apps work offline?",
      answer:
        "Yes, with local models. Superwhisper documents on-device models that work without internet. In VoiceToText, Parakeet, the default, works with the network off after a one-time download. Its Whisper models also run on the Mac, but loading one needs an internet connection.",
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
      label: "Superwhisper: Voice to text for Mac",
      href: "https://superwhisper.com/voice-to-text-mac",
      detail:
        "Vendor page for Mac support, cursor insertion, local operation, push-to-talk, file transcription, platform positioning, and its own comparison claims.",
    },
    {
      label: "Superwhisper: Models",
      href: "https://superwhisper.com/models",
      detail:
        "Vendor’s current catalog separating on-device and cloud transcription choices, languages, and product tiers.",
    },
    {
      label: "Superwhisper: Offline transcription",
      href: "https://superwhisper.com/offline-transcription",
      detail:
        "Vendor explanation of local model downloads, offline operation, hardware considerations, and its browser-versus-app privacy distinction.",
    },
    {
      label: "Superwhisper: Meeting transcription",
      href: "https://superwhisper.com/meeting-transcription",
      detail: "Vendor page for on-device meeting recording without a bot, speaker labels and file transcription.",
    },
    {
      label: "Superwhisper: Changelog",
      href: "https://superwhisper.com/changelog",
      detail:
        "Primary version history used to date the current macOS requirement and avoid relying on an older review.",
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
  title: "Wispr Flow Alternative for Mac: Free, Offline, No Account",
  description:
    "VoiceToText vs Wispr Flow on Mac: local vs cloud transcription, meetings and AI summaries, privacy controls, price, and which app suits whom.",
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
          "Free plan (2,000 words a week on desktop); Pro $15/user/month, or $12 billed annually",
        ],
      },
      {
        label: "Platforms",
        cells: ["Mac: Apple Silicon, macOS 15+", "Mac (macOS 12+, Intel or Apple Silicon), Windows, iPhone, Android"],
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
          ISO 27001 materials in its Trust Center. Flow also supports Intel Macs and macOS 12 or later, which
          VoiceToText doesn’t. Platform and deployment fit can matter more than where the speech model runs.
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
            "Parakeet (25 European languages) and five Whisper sizes (English in VoiceToText) run on Apple Silicon after the model download. VoiceToText runs no server, so there is nowhere for it to send your recording.",
        },
        {
          title: "No account",
          body:
            "Download from GitHub Releases and dictate without signing in. Optional cloud models and AI features use API keys you paste in, billed by OpenAI or ElevenLabs.",
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
          VoiceToText runs on one platform: macOS 15 or later on Apple Silicon. It has no Windows, iPhone or
          Android app, no team dashboard, no single sign-on, and no cross-device sync.
        </>,
        <>
          Flow polishes every dictation automatically. VoiceToText doesn’t: with a local model you get the
          model’s punctuated transcript, with no filler removal or voice commands, and AI cleanup happens only
          when you run an action on your own OpenAI key. With a local model the text also appears when you
          stop, not as you speak. Live text needs one of the cloud streaming models.
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
          "On the Mac with Parakeet or Whisper; optional OpenAI or ElevenLabs models are chosen separately and use your key.",
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
          "macOS 15+ on Apple Silicon.",
          "Mac (macOS 12+, Apple Silicon or Intel), Windows 10/11, iPhone (iOS 18.3+), Android 13–16.",
        ],
      },
      {
        label: "Languages",
        cells: [
          "Parakeet: 25 European languages, automatic. Local Whisper: English. Cloud models: 90–99+, detected automatically.",
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
          "Free plan with 2,000 words a week on desktop; Pro $15/user/month or $12 billed annually; Growth and Enterprise plans for teams.",
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
        "Yes. VoiceToText is free with no paid tier and no account. It transcribes on your Mac with local models and pastes the text into any app. It runs only on Apple Silicon Macs with macOS 15 or later.",
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
        "No. VoiceToText is Mac-only and needs Apple Silicon. Wispr Flow has apps for Mac, Windows, iPhone and Android.",
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
