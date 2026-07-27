import type { SeoLandingConfig } from "./seo-landing";

export const appleDictationAlternativeConfig: SeoLandingConfig = {
  path: "/apple-dictation-alternative",
  title: "Apple Dictation Alternative for Mac — Free & Offline",
  description:
    "Compare Apple Dictation with VoiceToText for Mac: installation, privacy, review, model choice, meeting capture, and the situations where the built-in tool wins.",
  breadcrumb: "Apple Dictation alternative",
  eyebrow: "Balanced comparison",
  readingTime: "9 min",
  h1: "An Apple Dictation alternative for people who want review, model choice, and local meeting transcripts.",
  lead:
    "Apple Dictation is already on every Mac and is often the right answer for quick text. VoiceToText adds an editable review step, selectable local engines, file and meeting transcription, and inspectable open-source code.",
  heroPoints: [
    "Reviewed July 27, 2026",
    "No pricing claims",
    "Primary Apple sources",
    "Clear tradeoffs",
  ],
  summaryTitle: "Should you switch?",
  summary: (
    <>
      Stay with Apple Dictation if you want a built-in tool with no installation and its text-entry workflow
      already fits. Try VoiceToText if you want to review a complete transcript before it touches the current
      app, choose between local speech models, import recordings, capture meeting audio, or audit the
      implementation. They can coexist, so the lowest-risk comparison is to test both on the same sentences.
    </>
  ),
  sections: [
    {
      id: "apple-strengths",
      eyebrow: "Where Apple wins",
      title: "Built in, broadly integrated, and good enough for many short messages.",
      paragraphs: [
        <>
          Apple Dictation requires no third-party download. Turn it on in System Settings → Keyboard, choose a
          language and microphone, and use the configured shortcut or microphone key in an app with a text
          field. Apple documents automatic punctuation in supported languages, spoken punctuation and emoji,
          and simple formatting commands.
        </>,
        <>
          On Apple silicon, Apple says you can continue typing while you speak. Its current guide also says
          dictation can accept text of any length, although it stops after 30 seconds without detected speech.
          These details make the built-in tool a strong baseline—not a feature to dismiss simply because an
          alternative exists.
        </>,
        <>
          Privacy behavior is conditional rather than something this comparison should oversimplify. Apple
          tells users to check Keyboard settings to see whether a selected language needs the internet and
          whether general text Dictation is processed on-device. That setting is the authoritative answer for
          a particular Mac and language.
        </>,
      ],
    },
    {
      id: "why-vtt",
      eyebrow: "Where VoiceToText differs",
      title: "A staged transcript changes how dictation feels.",
      cards: [
        {
          title: "Review before paste",
          body:
            "VoiceToText can hold the complete transcript in a floating editor. Correct names, numbers, and negations, then press Return—or disable review for instant paste.",
        },
        {
          title: "Choose a local engine",
          body:
            "Switch among Parakeet and several Whisper sizes. This gives you a concrete speed, language, and model-size choice rather than one system dictation engine.",
        },
        {
          title: "Keep the recording workflow",
          body:
            "Import an audio or video file, or capture microphone plus Mac system audio for a meeting, then keep audio and transcript together in local history.",
        },
        {
          title: "Inspect and automate",
          body:
            "The app is open source on GitHub and exposes a URL scheme for integrations. That is useful when auditability or a programmable workflow matters.",
        },
      ],
    },
    {
      id: "costs",
      eyebrow: "What the alternative costs",
      title: "VoiceToText is free, but third-party software still asks more of you.",
      paragraphs: [
        <>
          VoiceToText must be downloaded and updated separately. Current builds require macOS 15 or later and
          an Apple Silicon Mac. Apple Dictation follows the Mac’s operating-system support instead of adding
          another app-specific requirement.
        </>,
        <>
          To paste into another app, VoiceToText asks for Accessibility permission. Meeting recording also
          asks for Microphone and Screen Recording permission because macOS exposes system audio through that
          route. Apple Dictation is a system feature and does not ask you to trust a separate open-source
          application with the same cross-app workflow.
        </>,
        <>
          Local VoiceToText models take disk space and need an initial download. The project has no paid tier
          or app account, but it also does not promise enterprise support, cross-device sync, or Apple-level
          platform integration. “Free” does not erase those operational tradeoffs.
        </>,
      ],
      note:
        "If your only problem is that Apple Dictation is disabled, troubleshoot the built-in feature before installing anything. Check Keyboard settings, the microphone source, language availability, and the shortcut first.",
    },
    {
      id: "decision",
      eyebrow: "Choose by workflow",
      title: "Use the smallest tool that solves the actual problem.",
      cards: [
        {
          title: "Choose Apple Dictation",
          body:
            "You want no installation, already like direct insertion at the cursor, and do not need a persistent recording, model selector, or pre-paste transcript editor.",
        },
        {
          title: "Choose VoiceToText",
          body:
            "You want local model choice, reviewed paste, meeting or file transcription, an on-device history, or source code you can examine.",
        },
        {
          title: "Use both",
          body:
            "Keep Apple’s shortcut for quick low-stakes phrases and assign VoiceToText a separate shortcut for longer prompts, private files, or meetings.",
        },
        {
          title: "Choose Voice Control instead",
          body:
            "If the main need is navigating the interface and issuing spoken editing commands—not merely converting speech to prose—Apple Voice Control is the more relevant system feature.",
        },
      ],
    },
  ],
  comparison: {
    caption:
      "Feature behavior reviewed against Apple’s Mac User Guide and the VoiceToText project on July 27, 2026.",
    columns: ["VoiceToText", "Apple Dictation"],
    rows: [
      {
        label: "Install",
        cells: ["Third-party app downloaded from GitHub Releases.", "Built into macOS and enabled in Keyboard settings."],
      },
      {
        label: "Text flow",
        cells: [
          "Record, optionally review the complete transcript, then paste at the cursor.",
          "Dictates directly at the insertion point; ambiguous words may be offered as alternatives.",
        ],
      },
      {
        label: "On-device status",
        cells: [
          "Parakeet and Whisper run locally after download; cloud engines are optional and explicit.",
          "Apple says to check Keyboard settings because internet and on-device behavior can vary by language and context.",
        ],
      },
      {
        label: "Model choice",
        cells: ["Selectable Parakeet and Whisper variants.", "No user-facing third-party model selector."],
      },
      {
        label: "Recorded media",
        cells: ["Imports files and records microphone plus Mac system audio.", "Apple’s guide describes live text Dictation, not a meeting/file transcript library."],
      },
      {
        label: "Source access",
        cells: ["Public project source on GitHub.", "macOS system implementation is not open source."],
      },
      {
        label: "Requirements",
        cells: ["Current release: macOS 15+ and Apple Silicon.", "Depends on current macOS and feature availability for the selected language."],
      },
      {
        label: "Price",
        cells: ["Free and open source.", "Included with macOS."],
      },
    ],
    note:
      "This table compares documented behavior, not transcript accuracy. Accuracy depends on language, speaker, microphone, environment, vocabulary, and the specific software release.",
  },
  sources: [
    {
      label: "Apple: Dictate messages and documents",
      href: "https://support.apple.com/guide/mac-help/dictate-messages-and-documents-mh40584/mac",
      detail:
        "Apple’s primary setup and usage guide, including shortcuts, typing while speaking, punctuation, languages, internet/on-device notes, and stopping behavior.",
    },
    {
      label: "Apple: Keyboard settings",
      href: "https://support.apple.com/guide/mac-help/keyboard-settings-kbdm162/mac",
      detail:
        "Apple’s reference for Dictation languages, microphone source, shortcut, auto-punctuation, and privacy information available in System Settings.",
    },
    {
      label: "Apple: Voice Control commands",
      href: "https://support.apple.com/guide/mac-help/use-voice-control-commands-mh40719/mac",
      detail:
        "Primary documentation for Apple’s broader voice-navigation and text-editing feature, which is distinct from standard Dictation.",
    },
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail:
        "The implementation and release documentation for VoiceToText’s shortcut, permissions, local models, review flow, history, and recording features.",
    },
  ],
  related: [
    {
      href: "/how-to-use-voice-to-text-on-mac",
      title: "How to use voice to text on Mac",
      description: "A step-by-step VoiceToText setup guide for permissions, shortcuts, review, and paste.",
    },
    {
      href: "/offline-speech-to-text-mac",
      title: "Offline speech to text on Mac",
      description: "See exactly what stays local, which network connections remain, and how to verify the boundary.",
    },
    {
      href: "/whisper-vs-parakeet-mac",
      title: "Whisper vs. Parakeet",
      description: "Compare the local engines available inside VoiceToText without relying on a universal benchmark claim.",
    },
  ],
  ctaTitle: "You do not have to uninstall Apple Dictation.",
  ctaBody:
    "Give VoiceToText a different shortcut, dictate the same paragraph with both tools, and keep the workflow that makes fewer corrections on your Mac.",
  analyticsPlacement: "apple_alternative",
};

export const whisperVsParakeetConfig: SeoLandingConfig = {
  path: "/whisper-vs-parakeet-mac",
  title: "Whisper vs. Parakeet on Mac — Which Local Model?",
  description:
    "Compare Whisper and NVIDIA Parakeet for local speech to text on Mac: languages, model choices, responsiveness, limitations, and how to test your own audio.",
  breadcrumb: "Whisper vs. Parakeet on Mac",
  eyebrow: "Local model guide",
  readingTime: "10 min",
  h1: "Whisper vs. Parakeet on Mac: choose with your audio, not a leaderboard headline.",
  lead:
    "VoiceToText offers both model families locally. Parakeet is the practical starting point for responsive dictation; Whisper offers several sizes and broad multilingual experience. The right answer depends on your language, Mac, microphone, and vocabulary.",
  heroPoints: [
    "Reviewed July 27, 2026",
    "Primary model sources",
    "No universal accuracy winner",
    "Test methodology included",
  ],
  summaryTitle: "A sensible default",
  summary: (
    <>
      Start with Parakeet for frequent English dictation and a low-friction default. Try Whisper Large v3
      Turbo or Large v3 when multilingual speech, accents, or difficult recordings justify a heavier model.
      Keep the faster option only if it preserves the names, negations, numbers, and domain terms that matter
      in your work.
    </>
  ),
  sections: [
    {
      id: "families",
      eyebrow: "Understand the choice",
      title: "These are model families, not two fixed settings.",
      paragraphs: [
        <>
          Whisper is OpenAI’s open speech-recognition and speech-translation model family. Its official model
          card documents multiple sizes, multilingual models, and translation into English. VoiceToText ships
          local options from Tiny through Large v3 and Large v3 Turbo via WhisperKit, giving users an explicit
          storage, memory, and inference tradeoff.
        </>,
        <>
          Parakeet is NVIDIA’s family of automatic speech-recognition models built with a FastConformer encoder
          and CTC, RNN-T, or TDT decoders. VoiceToText’s local Parakeet path uses Parakeet TDT v3 through
          FluidAudio. NVIDIA’s current checkpoint documentation lists the 0.6B v3 model with transcription,
          punctuation/capitalization, and timestamps.
        </>,
        <>
          The application wrapper matters too. VoiceToText runs converted, Apple-optimized implementations,
          not the reference PyTorch or NeMo commands shown in the upstream repositories. Do not transfer a
          vendor benchmark from different hardware and decoding settings directly to a particular Mac app.
        </>,
      ],
    },
    {
      id: "parakeet",
      eyebrow: "Why start with Parakeet",
      title: "A responsive default is valuable when dictation happens dozens of times a day.",
      cards: [
        {
          title: "Designed for fast ASR",
          body:
            "NVIDIA describes Parakeet TDT as a fast speech-recognition family. In VoiceToText, Parakeet is positioned as the default local option for quick everyday dictation.",
        },
        {
          title: "Punctuation and capitalization",
          body:
            "The v3 checkpoint documentation includes punctuation and capitalization, useful for producing readable prose without a separate cleanup pass.",
        },
        {
          title: "One clear starting point",
          body:
            "A default removes model-size tuning from initial setup. Download it, dictate representative sentences, and move to Whisper only when a concrete problem appears.",
        },
        {
          title: "Check language support",
          body:
            "Parakeet releases differ. Verify that the exact model inside the app supports your language; do not assume a claim about v2, v3, or another checkpoint applies interchangeably.",
        },
      ],
    },
    {
      id: "whisper",
      eyebrow: "Why choose Whisper",
      title: "Whisper gives more knobs and a well-documented multilingual family.",
      paragraphs: [
        <>
          OpenAI’s model card lists Tiny, Base, Small, Medium, Large, and Turbo variants, with multilingual
          models across the family. VoiceToText exposes a useful subset: Tiny, Base, Small, Large v3, and Large
          v3 Turbo. Smaller options reduce local resource demands; the larger choices are intended for cases
          where transcript quality matters more than the shortest turnaround.
        </>,
        <>
          Whisper is also designed for speech translation into English. That does not mean every language
          performs equally. OpenAI explicitly warns that performance is uneven across languages and accents
          and that weakly supervised models can produce text that was not spoken. A broad training set is not
          a guarantee for one speaker.
        </>,
        <>
          Choose Whisper when you need its language coverage, want to compare model sizes, or find that it
          handles a recurring microphone, accent, or vocabulary pattern better. Keep a smaller model available
          for rapid drafts if the largest model slows down an interactive workflow.
        </>,
      ],
    },
    {
      id: "test",
      eyebrow: "Run a fair test",
      title: "Five minutes of representative audio beats a generic winner.",
      cards: [
        {
          title: "Use the same recording",
          body:
            "Record 60–90 seconds once, then regenerate the transcript with each model. Changing the model settings, microphone, or words makes the comparison less useful.",
        },
        {
          title: "Include your hard words",
          body:
            "Say names, product terms, acronyms, numbers, commands, and a sentence with negation. These errors matter more than easy filler words.",
        },
        {
          title: "Score what affects work",
          body:
            "Count meaning-changing errors and correction time. Also note startup and completion time on the Mac you actually use; do not rely on a GPU benchmark.",
        },
        {
          title: "Repeat in real conditions",
          body:
            "Try a quiet desk, headset, room microphone, and the accent or language mix you encounter. One clean sample can conceal the failure mode you care about.",
        },
      ],
      note:
        "For important transcripts, preserve the recording and review the text against it. Neither family should be treated as authoritative in medical, legal, safety, or other high-risk decisions.",
    },
  ],
  comparison: {
    caption:
      "Model-family characteristics relevant to VoiceToText; exact behavior depends on the selected checkpoint and app release.",
    columns: ["Parakeet TDT v3", "Whisper"],
    rows: [
      {
        label: "Practical role",
        cells: ["Responsive local default for regular dictation.", "Alternative family with several local size choices."],
      },
      {
        label: "Upstream developer",
        cells: ["NVIDIA.", "OpenAI."],
      },
      {
        label: "Choices in VoiceToText",
        cells: ["One Parakeet TDT v3 option.", "Large v3 Turbo, Large v3, Small, Base, and Tiny."],
      },
      {
        label: "Language decision",
        cells: [
          "Check support for the exact Parakeet checkpoint in the installed app.",
          "Broad multilingual family; OpenAI documents uneven performance by language and accent.",
        ],
      },
      {
        label: "Local implementation",
        cells: ["FluidAudio on Apple hardware.", "WhisperKit on Apple hardware."],
      },
      {
        label: "What can go wrong",
        cells: [
          "Unsupported language or a vocabulary pattern that the model handles poorly.",
          "Resource cost, uneven language/accent results, and possible hallucinated text documented by OpenAI.",
        ],
      },
      {
        label: "Best test",
        cells: [
          "Compare correction time on frequent, short dictations.",
          "Compare the same saved recording across the relevant model sizes.",
        ],
      },
    ],
    note:
      "No word-error-rate number is shown because a number from a different dataset, decoder, runtime, or processor would not establish performance in this Mac application.",
  },
  sources: [
    {
      label: "OpenAI Whisper model card",
      href: "https://github.com/openai/whisper/blob/main/model-card.md",
      detail:
        "Primary documentation for tasks, model sizes, training languages, intended use, uneven performance, and hallucination limitations.",
    },
    {
      label: "OpenAI Whisper repository",
      href: "https://github.com/openai/whisper",
      detail:
        "The reference implementation and current list of model sizes, language behavior, and approximate hardware tradeoffs in the upstream project.",
    },
    {
      label: "NVIDIA NeMo ASR checkpoints",
      href: "https://docs.nvidia.com/nemo/speech/nightly/asr/asr_checkpoints.html",
      detail:
        "NVIDIA’s current checkpoint table for Parakeet variants, decoder type, tasks, languages, and model size.",
    },
    {
      label: "NVIDIA NeMo featured models",
      href: "https://docs.nvidia.com/nemo/speech/nightly/asr/featured_models.html",
      detail:
        "Primary overview of the Parakeet family and NVIDIA’s positioning of current TDT checkpoints.",
    },
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail:
        "The app’s source and release documentation for the WhisperKit and FluidAudio integrations described on this page.",
    },
  ],
  related: [
    {
      href: "/offline-speech-to-text-mac",
      title: "Offline speech to text on Mac",
      description: "Understand the network boundary for both local engines and the optional cloud models.",
    },
    {
      href: "/voice-to-text-for-coding",
      title: "Voice to text for coding",
      description: "Apply local dictation to prompts, bug reports, review notes, and documentation.",
    },
    {
      href: "/how-to-use-voice-to-text-on-mac",
      title: "Mac voice-to-text setup",
      description: "Install a model, grant permissions, select a shortcut, review, and paste.",
    },
  ],
  ctaTitle: "Compare both models on one saved recording.",
  ctaBody:
    "Use your real microphone, language, names, and technical vocabulary. Keep the engine that minimizes meaning-changing corrections on your Mac.",
  analyticsPlacement: "model_comparison",
};
