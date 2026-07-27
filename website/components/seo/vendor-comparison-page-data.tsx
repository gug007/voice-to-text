import type { SeoLandingConfig } from "./seo-landing";

export const superwhisperAlternativeConfig: SeoLandingConfig = {
  path: "/superwhisper-alternative",
  title: "Superwhisper Alternative for Mac — Free & Open Source",
  description:
    "Compare VoiceToText and Superwhisper for Mac dictation: local models, platforms, formatting, file workflows, source access, requirements, and who each app suits.",
  breadcrumb: "Superwhisper alternative",
  eyebrow: "Balanced comparison",
  readingTime: "10 min",
  h1: "A Superwhisper alternative for Mac users who prioritize free, inspectable, local-first software.",
  lead:
    "Superwhisper is a mature, cross-platform voice product with local and cloud models, AI formatting, and a wider ecosystem. VoiceToText is a narrower Mac app: free, open source, local by default, and built around reviewed paste plus meeting capture.",
  heroPoints: [
    "Reviewed July 27, 2026",
    "No unverifiable prices",
    "Official vendor sources",
    "Both products credited",
  ],
  summaryTitle: "Which one should you try?",
  summary: (
    <>
      Choose Superwhisper when cross-platform availability, its Super Mode formatting, broad model catalog,
      iOS continuity, and an established commercial product matter. Choose VoiceToText when you want a
      no-cost open-source Mac utility, no app account, a simple review-before-paste flow, and local meeting or
      file transcription. Test both with your language and vocabulary; this page does not claim one model is
      universally more accurate.
    </>
  ),
  sections: [
    {
      id: "superwhisper-case",
      eyebrow: "The case for Superwhisper",
      title: "It covers more platforms and more layers of the writing workflow.",
      paragraphs: [
        <>
          Superwhisper’s official site describes system-wide dictation for macOS, Windows, and iOS. It can
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
          title: "Free and open source",
          body:
            "The application source is public and the release has no paid tier, account, or in-app subscription. You can inspect how audio, permissions, history, and paste behavior are implemented.",
        },
        {
          title: "Local by default",
          body:
            "Parakeet and Whisper run on Apple Silicon after model download. Optional cloud models require your own provider key and are a deliberate selection rather than the default path.",
        },
        {
          title: "Review as the core workflow",
          body:
            "Stop dictation, correct the complete transcript in a floating panel, and press Return to paste. You can turn review off, but the safe staged workflow remains first-class.",
        },
        {
          title: "Meetings without a bot",
          body:
            "Capture the Mac’s microphone and system audio, transcribe locally, keep the recording in history, and regenerate with another model when needed.",
        },
      ],
    },
    {
      id: "tradeoffs",
      eyebrow: "Tradeoffs to accept",
      title: "VoiceToText is not a drop-in copy of the broader product.",
      paragraphs: [
        <>
          VoiceToText currently targets macOS 15 or later on Apple Silicon. It does not offer Windows or iOS
          clients, a cross-device sync story, or the same catalog of vendor-hosted and local engines described
          by Superwhisper. If you dictate across phone and desktop, platform reach may decide the comparison
          immediately.
        </>,
        <>
          VoiceToText includes optional AI transcript actions, but its primary local flow preserves what was
          transcribed for review. Superwhisper’s marketing emphasizes context-aware cleanup and formatting.
          Users who want an assistant to reshape every utterance may prefer that product; users who want to
          see and edit the raw result may prefer a simpler boundary.
        </>,
        <>
          Open source is valuable for auditability and community modification, but it is not the same as a
          support contract or security certification. Evaluate the maintenance model, release cadence, and
          support expectations that apply to your organization.
        </>,
      ],
      note:
        "Both products offer local transcription. “Superwhisper alternative” here means a different product and governance model, not a claim that Superwhisper is cloud-only.",
    },
    {
      id: "decision",
      eyebrow: "Choose by priority",
      title: "Write down the non-negotiable before comparing transcript output.",
      cards: [
        {
          title: "Pick Superwhisper for reach",
          body:
            "You need supported clients beyond one Mac, want its context-aware formatting and model catalog, or prefer a commercial product ecosystem.",
        },
        {
          title: "Pick VoiceToText for inspectability",
          body:
            "You want an open repository, no app account, a free feature set, explicit local-model selection, and a Mac-native review workflow.",
        },
        {
          title: "Compare local mode to local mode",
          body:
            "Do not compare a small local model in one product with a cloud model in the other and call it a product verdict. Match the privacy and processing mode first.",
        },
        {
          title: "Use a personal test set",
          body:
            "Dictate the same names, technical terms, accent, and sentence lengths into both. Measure corrections and total time—not just the first impressive sample.",
        },
      ],
    },
  ],
  comparison: {
    caption:
      "Documented product behavior reviewed on July 27, 2026. Plans, models, and requirements can change.",
    columns: ["VoiceToText", "Superwhisper"],
    rows: [
      {
        label: "Platforms",
        cells: ["macOS.", "Official site lists macOS, Windows, and iOS."],
      },
      {
        label: "Source model",
        cells: ["Open-source application on GitHub.", "Commercial proprietary application."],
      },
      {
        label: "Local transcription",
        cells: [
          "Parakeet and Whisper options run on the Mac after download.",
          "Official model catalog lists on-device models that work without internet.",
        ],
      },
      {
        label: "Cloud transcription",
        cells: [
          "Optional OpenAI and ElevenLabs choices use the user’s provider key.",
          "Official catalog lists vendor-proxied cloud models as well as on-device choices.",
        ],
      },
      {
        label: "Output workflow",
        cells: [
          "Review the complete transcript before paste, or enable instant paste; optional transcript actions.",
          "System-wide dictation plus modes and AI/context-aware formatting promoted by the vendor.",
        ],
      },
      {
        label: "Recorded media",
        cells: [
          "File import plus microphone and system-audio meeting capture with local history.",
          "Official site documents file transcription; check the current app for the exact meeting workflow.",
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
          "Free with no paid tier.",
          "Free tier plus paid features; verify current plan details with the vendor.",
        ],
      },
    ],
    note:
      "Neither column is an accuracy score. Model selection, audio, language, hardware, and formatting settings can change the result more than the product name alone.",
  },
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
      title: "Wispr Flow alternative",
      description: "Compare a local-first open-source Mac app with a cloud transcription product and its privacy controls.",
    },
    {
      href: "/offline-speech-to-text-mac",
      title: "Offline speech to text on Mac",
      description: "Verify what local transcription means and where optional network features begin.",
    },
    {
      href: "/whisper-vs-parakeet-mac",
      title: "Whisper vs. Parakeet",
      description: "Choose between the two local model families available in VoiceToText.",
    },
  ],
  ctaTitle: "Compare the workflow, not just the feature list.",
  ctaBody:
    "Use the same paragraph and privacy mode in both apps. Count corrections, review time, and friction across a normal workday.",
  analyticsPlacement: "superwhisper_alternative",
};

export const wisprFlowAlternativeConfig: SeoLandingConfig = {
  path: "/wispr-flow-alternative",
  title: "Wispr Flow Alternative for Mac — Local & Open Source",
  description:
    "Compare VoiceToText and Wispr Flow for Mac dictation: local versus cloud transcription, privacy controls, platforms, accounts, formatting, and tradeoffs.",
  breadcrumb: "Wispr Flow alternative",
  eyebrow: "Balanced comparison",
  readingTime: "11 min",
  h1: "A Wispr Flow alternative for Mac users who want transcription to run locally.",
  lead:
    "Wispr Flow is a polished cross-platform cloud dictation product with AI editing, context, personalization, and enterprise controls. VoiceToText is a free open-source Mac app whose Parakeet and Whisper engines can transcribe without sending audio to a server.",
  heroPoints: [
    "Reviewed July 27, 2026",
    "Current privacy docs",
    "No stale pricing table",
    "Cloud strengths acknowledged",
  ],
  summaryTitle: "The deciding difference",
  summary: (
    <>
      If audio must be transcribed on the Mac, choose VoiceToText with a local model: Wispr’s official privacy
      page says Flow transcription always happens in the cloud. If you value Flow’s cross-device clients,
      context-aware polishing, personalization, notetaking ecosystem, and managed enterprise controls, its
      cloud architecture may be an acceptable trade. Privacy settings and cloud storage are separate
      decisions in Flow, so inspect both before dictating sensitive material.
    </>
  ),
  sections: [
    {
      id: "flow-case",
      eyebrow: "The case for Wispr Flow",
      title: "A cloud service can coordinate features that a single-device utility does not attempt.",
      paragraphs: [
        <>
          Wispr’s official documentation lists clients for Mac, Windows, iOS, and Android (Beta). Its product combines
          dictation with AI commands and automatic edits, context awareness, a dictionary, snippets,
          personalization, and a Scratchpad/notetaking workflow. Those features are designed to make output
          ready for the destination rather than simply expose a raw transcript.
        </>,
        <>
          The cloud design supports consistent service behavior across devices and organization-level
          controls. Wispr documents SSO/SAML for enterprise plans, administrator-enforced privacy settings,
          and security and compliance materials. Because attestation status can change, verify the current
          scope and status in Wispr’s Trust Center. Teams that require managed controls may prefer a vendor
          service over a community-maintained desktop utility.
        </>,
        <>
          Flow also supports Intel Macs and older macOS versions than current VoiceToText releases, according
          to Wispr’s July 2026 “What is Flow?” documentation. Platform and deployment fit can matter more than
          whether a speech model is local.
        </>,
      ],
    },
    {
      id: "privacy",
      eyebrow: "Read the controls carefully",
      title: "Cloud processing, training choice, and server storage are three different questions.",
      paragraphs: [
        <>
          Wispr’s privacy page says transcription always happens in the cloud. Privacy Mode controls whether
          dictation data is used to train or improve models; turning it on does not, by itself, move inference
          onto the device.
        </>,
        <>
          Private Cloud Sync separately controls server-side storage and features that depend on it. Wispr’s
          July 2026 documentation says that enabling Privacy Mode and disabling Private Cloud Sync provides
          zero data retention for dictation data, while some notetaking, sync, and personalization features
          require cloud storage.
        </>,
        <>
          These are meaningful controls, not evidence that Flow is careless. They simply solve a different
          problem from on-device inference. An organization may prefer a contractually managed cloud service;
          another may have a policy that recordings cannot be sent to any transcription server at all.
        </>,
      ],
      note:
        "Flow’s two-control privacy experience was rolling out gradually in July 2026. Check the exact settings visible in your account and current vendor documentation instead of assuming a screenshot from another device applies.",
    },
    {
      id: "vtt-case",
      eyebrow: "The case for VoiceToText",
      title: "Local-first design reduces the number of parties in the audio path.",
      cards: [
        {
          title: "On-device engines",
          body:
            "Parakeet and Whisper run on Apple Silicon after the model download. The recording is not sent to VoiceToText because the project operates no transcription server.",
        },
        {
          title: "No app account",
          body:
            "Install from GitHub Releases and use local dictation without signing in. Optional cloud engines and AI actions use API keys you provide directly.",
        },
        {
          title: "Inspectable implementation",
          body:
            "The Swift source is public. Users and security teams can review permissions, storage, update checks, model code paths, and paste behavior.",
        },
        {
          title: "Local recording history",
          body:
            "Meeting and file audio can remain with their transcripts on the Mac. That keeps control close, but also makes local disk protection and retention the user’s responsibility.",
        },
      ],
    },
    {
      id: "tradeoffs",
      eyebrow: "What local-first does not give you",
      title: "Privacy architecture is only one dimension of product fit.",
      paragraphs: [
        <>
          VoiceToText supports one platform: current builds require macOS 15 or later and Apple Silicon. It
          does not provide Flow’s Windows, iOS, or Android clients, organization dashboard, enterprise identity
          features, or a cross-device cloud notebook.
        </>,
        <>
          Flow’s product is built around AI rewriting, context, and personalization. VoiceToText offers a
          review editor and optional transcript actions, but users who expect every dictation to be
          automatically adapted to an app and personal style may find the local-first utility intentionally
          simpler.
        </>,
        <>
          VoiceToText has no first-party service charge, but local models consume disk and processing resources,
          and the project does not promise a commercial SLA. Flow has plan limits and paid offerings that can
          change; consult its current pricing page rather than relying on an undated comparison.
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
            "Use VoiceToText with Parakeet or Whisper. Verify the selected model and avoid its optional cloud engines and AI actions for that session.",
        },
        {
          title: "Need cross-platform continuity?",
          body:
            "Flow has the stronger documented platform story. Decide whether its cloud processing and account model fit the data involved.",
        },
        {
          title: "Need managed compliance controls?",
          body:
            "Evaluate Wispr’s current security documentation, agreements, admin controls, and Trust Center rather than inferring compliance from a local app.",
        },
        {
          title: "Need transparent, hackable software?",
          body:
            "VoiceToText’s public repository and URL-scheme automation are the more direct fit, with the maintenance tradeoffs of an open-source project.",
        },
      ],
    },
  ],
  comparison: {
    caption:
      "Documented product behavior reviewed on July 27, 2026. Confirm current settings and plan details before making a policy decision.",
    columns: ["VoiceToText", "Wispr Flow"],
    rows: [
      {
        label: "Transcription location",
        cells: [
          "Local with Parakeet or Whisper; optional cloud engines are separately selected.",
          "Wispr’s privacy page says transcription always happens in the cloud.",
        ],
      },
      {
        label: "Account",
        cells: [
          "No VoiceToText account for the local app.",
          "Desktop sign-in goes through Wispr’s web login, according to its product documentation.",
        ],
      },
      {
        label: "Platforms",
        cells: [
          "macOS on Apple Silicon.",
          "Official documentation lists Mac, Windows, iOS, and Android (Beta).",
        ],
      },
      {
        label: "Privacy controls",
        cells: [
          "Select a local model so audio does not leave the Mac; the app has no first-party transcription server.",
          "Privacy Mode controls training use; Private Cloud Sync separately controls server storage and dependent features.",
        ],
      },
      {
        label: "Output processing",
        cells: [
          "Review-before-paste or instant paste, with optional user-keyed transcript actions.",
          "AI commands, auto-edits, context awareness, personalization, dictionary, and snippets documented by Wispr.",
        ],
      },
      {
        label: "Meetings and notes",
        cells: [
          "Local microphone + system-audio recording, file import, playback, and transcript history.",
          "Notetaker and meeting-note features are part of Flow’s cloud-connected ecosystem; some require Private Cloud Sync.",
        ],
      },
      {
        label: "Governance",
        cells: [
          "Open-source application; no commercial support or compliance claim made here.",
          "Proprietary service with vendor-documented enterprise and security controls; verify current attestations in its Trust Center.",
        ],
      },
      {
        label: "Payment model",
        cells: [
          "Free with no paid tier.",
          "Plan-based service; verify current limits and pricing with Wispr.",
        ],
      },
    ],
    note:
      "Zero data retention is not the same as on-device transcription: data can be processed in the cloud and discarded. Decide which requirement your policy actually sets.",
  },
  sources: [
    {
      label: "Wispr Flow: Privacy",
      href: "https://wisprflow.ai/privacy",
      detail:
        "Vendor overview of Privacy Mode, Private Cloud Sync, zero data retention, security claims, and the statement that transcription happens in the cloud.",
    },
    {
      label: "Wispr Flow: Data controls",
      href: "https://docs.wisprflow.ai/articles/9609615338-private-cloud-sync-and-data-sharing-preferences-in-wispr-flow",
      detail:
        "July 2026 vendor documentation separating model-training preference from cloud storage and listing features that depend on sync.",
    },
    {
      label: "Wispr Flow: Security FAQ",
      href: "https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq",
      detail:
        "Vendor details on data handling, Privacy Mode, cloud sync, certifications, organization controls, and product security.",
    },
    {
      label: "Wispr Flow: What is Flow?",
      href: "https://docs.wisprflow.ai/articles/2772472373-what-is-flow",
      detail:
        "Current vendor platform and system-requirement documentation, including sign-in and device-specific limitations.",
    },
    {
      label: "Wispr Flow: What’s new",
      href: "https://wisprflow.ai/whats-new",
      detail:
        "Dated vendor history for the July 2026 split between Privacy Mode and Cloud Sync.",
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
      title: "Superwhisper alternative",
      description: "Compare two products that both offer local transcription but differ in platform reach and governance.",
    },
    {
      href: "/offline-speech-to-text-mac",
      title: "Offline speech to text on Mac",
      description: "See the exact boundary between local models, update checks, optional cloud engines, and AI actions.",
    },
    {
      href: "/apple-dictation-alternative",
      title: "Apple Dictation alternative",
      description: "Compare VoiceToText with the built-in Mac baseline before adding a cloud service.",
    },
  ],
  ctaTitle: "Test the architecture your work requires.",
  ctaBody:
    "If on-device transcription is non-negotiable, download a local model, disconnect Wi-Fi, and verify the full VoiceToText workflow yourself.",
  analyticsPlacement: "wispr_alternative",
};
