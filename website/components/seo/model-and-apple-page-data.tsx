import Link from "next/link";

import {
  CATALOG_SNAPSHOT,
  CLOUD_PROVIDERS_AND,
  CLOUD_PROVIDERS_OR,
  cheapestCloudModel,
  cloudModels,
  DOWNLOAD_SIZE_NOTE,
  QUALITY_SCORE_SOURCES,
  formatDownloadSize,
  formatPrice,
  formatQuality,
  localModels,
  modelById,
  type ModelFact,
  type WerBenchmark,
} from "@/lib/app-facts";
import { formatDisplayDate, page } from "@/lib/pages";
import { countWord } from "@/lib/seo";

import type { SeoLandingConfig } from "./seo-landing";

const APPLE_SOURCES_CHECKED = formatDisplayDate(
  page("/apple-dictation-alternative").sourcesReviewed ?? page("/apple-dictation-alternative").published,
);

export const appleDictationAlternativeConfig: SeoLandingConfig = {
  path: "/apple-dictation-alternative",
  parent: { name: "Compare", path: "/compare" },
  title: "Apple Dictation Alternative for Mac (2026): Free & Offline",
  description:
    "Apple Dictation vs VoiceToText on Mac: install, privacy, review before paste, model choice, meeting capture, and when the built-in tool wins.",
  breadcrumb: "Apple Dictation alternative",
  eyebrow: "Balanced comparison",
  readingTime: "7 min",
  h1: "An Apple Dictation alternative for people who want review, model choice, and local meeting transcripts.",
  lead:
    "Apple Dictation is already on every Mac and is often the right answer for quick text. VoiceToText adds an editable review step, a choice of local and cloud models, meeting and file transcription with a searchable history, and source you can read on GitHub.",
  heroPoints: [
    "Both free to use",
    "Primary Apple sources",
    "Where Apple wins, too",
    "Test both side by side",
  ],
  summaryTitle: "Should you switch?",
  summary: (
    <>
      Stay with Apple Dictation if you want a built-in tool with no installation, spoken punctuation and
      editing commands, and its text-entry workflow already fits. Try VoiceToText if you want to review a
      complete transcript before it reaches the app, choose between speech models, record meetings, import
      recordings, or search everything you have said. They can run side by side, so the lowest-risk
      comparison is to dictate the same sentences with both.
    </>
  ),
  disclosure: (
    <>
      This is VoiceToText’s own website, written by its developer. There are no affiliate links or
      sponsorships. Apple’s behavior is described from its Mac User Guide, linked below; VoiceToText’s from
      its source code.
    </>
  ),
  atAGlance: {
    title: "VoiceToText vs Apple Dictation at a glance.",
    caption: `Apple Dictation as documented by Apple (checked ${APPLE_SOURCES_CHECKED}); VoiceToText as of ${CATALOG_SNAPSHOT}.`,
    columns: ["VoiceToText", "Apple Dictation"],
    rows: [
      { label: "Install", cells: ["Free download (macOS 15+, Apple Silicon or Intel)", "Built into macOS"] },
      { label: "Text flow", cells: ["Review, then paste; or instant paste", "Types live at the cursor"] },
      { label: "Spoken commands", cells: ["None; optional AI cleanup actions", "Spoken punctuation, emoji and formatting"] },
      { label: "Models", cells: [`${localModels().length} local + ${cloudModels().length} optional cloud`, "Apple’s system engine"] },
      { label: "Meetings and files", cells: ["Records calls and imports files; searchable history", "Not part of Dictation"] },
      { label: "Price", cells: ["Free; cloud and AI features bill your own key", "Included with macOS"] },
    ],
  },
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
          and simple formatting commands. VoiceToText has none of those voice commands.
        </>,
        <>
          On Apple silicon, Apple says you can continue typing while you speak. Its current guide also says
          dictation can accept text of any length, although it stops after 30 seconds without detected speech.
          These details make the built-in tool a strong baseline, not something to dismiss because an
          alternative exists.
        </>,
        <>
          Privacy behavior depends on the language, and this comparison shouldn’t oversimplify it. Apple
          tells users to check Keyboard settings to see whether a selected language needs the internet and
          whether general text Dictation is processed on-device. That setting is the authoritative answer for
          a particular Mac and language.
        </>,
      ],
    },
    {
      id: "why-vtt",
      eyebrow: "Where VoiceToText differs",
      title: "A staged transcript, a model choice, and a place for recordings.",
      cards: [
        {
          title: "Review before paste",
          body:
            "VoiceToText holds the complete transcript in a floating panel. Correct names, numbers and negations, press ⌘R to add another take at the caret, then press Return to paste. Turn review off for instant paste.",
        },
        {
          title: "Optional AI actions",
          body:
            "Six built-in actions (Clean transcript, To English, Improve prompt, Fix grammar, Summarize, Essentials only) plus your own, on ⌘1–⌘9 in the review panel. They are off by default and run on OpenAI with your key, which means the transcript text is sent there.",
        },
        {
          title: "Choose a model",
          body: (
            <>
              Six local models run on the Mac: Parakeet (the default, 25 European languages) and five Whisper
              sizes (99 languages). {cloudModels().length} optional cloud models from {CLOUD_PROVIDERS_AND} cover
              90 to 99+ languages and add live text, on your own API key. The{" "}
              <Link href="/whisper-vs-parakeet-mac">Whisper vs. Parakeet guide</Link> compares the local six.
            </>
          ),
        },
        {
          title: "Conversations and AI summaries",
          body: (
            <>
              Record a call’s microphone and system audio with no bot, or drop in an audio or video file. Each
              recording can get an AI summary, an action-item checklist or your own prompt’s result, on your
              OpenAI key. See <Link href="/meeting-recording">meeting recording</Link>.
            </>
          ),
        },
        {
          title: "A searchable history",
          body:
            "Dictations (unless you turn saving off), meetings and imports are kept on the Mac with their audio. Search covers transcripts, summaries, action items and speaker names, and any recording can be regenerated with another model.",
        },
        {
          title: "Inspect and automate",
          body:
            "The source is public on GitHub, and a voicetotext:// URL scheme lets Raycast, Shortcuts or a script start and stop dictation.",
        },
      ],
    },
    {
      id: "costs",
      eyebrow: "What the alternative costs",
      title: "VoiceToText is free, but third-party software still asks more of you.",
      paragraphs: [
        <>
          VoiceToText is a separate download. It checks GitHub for new versions and installs one with a
          click when you confirm, but that is still an app to keep up to date. Current builds require macOS 15
          or later on an Apple Silicon or Intel Mac. Apple Dictation follows the Mac’s operating-system support
          instead of adding another requirement.
        </>,
        <>
          To paste into another app, VoiceToText needs Accessibility permission, which it also needs to start
          recording. Meeting recording also asks for Microphone and Screen Recording permission, because
          macOS hands apps the system audio through Screen Recording. Apple Dictation is part of the system,
          so there is no separate app to trust with that access.
        </>,
        <>
          VoiceToText types nothing as you speak with a local model: text appears when you stop. It has no
          spoken punctuation, no voice editing commands and no language setting. Parakeet handles 25 European
          languages automatically; anything else needs a cloud model and an API key. Local models also take
          disk space and an initial download. There is no paid tier or account, but also no enterprise
          support, cross-device sync or Apple-level system integration.
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
            "You want no installation, like text appearing at the cursor as you speak, rely on spoken punctuation, and don’t need recordings, a model choice or a review step.",
        },
        {
          title: "Choose VoiceToText",
          body: (
            <>
              You want reviewed paste, a model choice, meeting or file transcription, a searchable history on
              the Mac, or source you can read. To see how it stacks up against paid apps too, browse{" "}
              <Link href="/compare">all comparisons</Link>.
            </>
          ),
        },
        {
          title: "Use both",
          body:
            "Keep Apple’s shortcut for quick, low-stakes phrases and give VoiceToText a different shortcut for longer prompts, private files or meetings.",
        },
        {
          title: "Choose Voice Control instead",
          body:
            "If the main need is navigating the interface and issuing spoken editing commands, rather than turning speech into prose, Apple Voice Control is the more relevant system feature.",
        },
      ],
      note: (
        <>
          Coming from Dragon? Dragon for Mac was discontinued in 2018.{" "}
          <Link href="/dragon-for-mac-alternative">Mac dictation vs. Dragon</Link> covers what replaced it, from
          Voice Control’s commands and custom vocabulary to VoiceToText.
        </>
      ),
    },
  ],
  comparison: {
    title: "VoiceToText vs Apple Dictation, in detail.",
    caption: `Apple’s behavior as documented in its Mac User Guide (checked ${APPLE_SOURCES_CHECKED}); VoiceToText as of ${CATALOG_SNAPSHOT}.`,
    columns: ["VoiceToText", "Apple Dictation"],
    rows: [
      {
        label: "Install",
        cells: [
          "Third-party app from GitHub Releases; checks for updates and installs them when you confirm.",
          "Built into macOS and enabled in Keyboard settings.",
        ],
      },
      {
        label: "Text flow",
        cells: [
          "Record, review the complete transcript (on by default), then paste at the cursor. ⌘R adds another take.",
          "Dictates directly at the insertion point; ambiguous words may be offered as alternatives.",
        ],
      },
      {
        label: "Spoken commands",
        cells: [
          "None. Words like “comma” are typed as words unless an optional AI action cleans them up.",
          "Spoken punctuation, emoji and simple formatting commands in supported languages.",
        ],
      },
      {
        label: "On-device status",
        cells: [
          "Parakeet and Whisper run locally after download, even with the network off. Cloud models and AI actions are optional and use your own key.",
          "Apple says to check Keyboard settings because internet and on-device behavior can vary by language and context.",
        ],
      },
      {
        label: "Languages",
        cells: [
          "Parakeet: 25 European languages, automatic. Local Whisper: 99 languages, automatic. Cloud models: 90–99+, detected automatically.",
          "Many languages; you choose them in Keyboard settings. Features vary by language.",
        ],
      },
      {
        label: "Recordings",
        cells: [
          "Records microphone plus Mac system audio, imports audio and video files, and keeps a searchable local history with optional AI summaries.",
          "Apple’s guide describes live text Dictation, not a meeting or file transcript library.",
        ],
      },
      {
        label: "Source access",
        cells: ["Source is public on GitHub.", "Part of macOS; the implementation is not public."],
      },
      {
        label: "Requirements",
        cells: ["macOS 15 or later, Apple Silicon or Intel.", "Depends on the macOS version and the selected language."],
      },
      {
        label: "Price",
        cells: [
          `Free. Cloud transcription and AI features bill your own ${CLOUD_PROVIDERS_OR} key.`,
          "Included with macOS.",
        ],
      },
    ],
    note:
      "This table compares documented behavior, not transcript accuracy. Accuracy depends on language, speaker, microphone, environment, vocabulary, and the specific software release.",
  },
  faq: [
    {
      question: "Is VoiceToText better than Apple Dictation?",
      answer:
        "For quick messages, Apple Dictation is often enough, and it supports spoken punctuation. VoiceToText is the better fit when you want to review text before it is pasted, choose a speech model, record meetings, or keep a searchable history.",
    },
    {
      question: "Does VoiceToText work offline like Apple’s on-device dictation?",
      answer:
        "Yes, with Parakeet, the default model: after a one-time download it transcribes on the Mac with the network off. The local Whisper models do too. Cloud models and AI features are optional and need the internet and your own API key.",
    },
    {
      question: "Can I use Apple Dictation and VoiceToText on the same Mac?",
      answer:
        "Yes. Give VoiceToText a shortcut that doesn't clash with Dictation's. Its default is Option+Space, and you can change it in Settings → Shortcut.",
    },
    {
      question: "Does VoiceToText understand spoken punctuation like “comma” or “new line”?",
      answer:
        "No. The model punctuates from how you speak, and spoken cues are typed as words. The optional Clean transcript or Fix grammar action turns them into formatting, using your OpenAI key.",
    },
    {
      question: "Does VoiceToText cost anything?",
      answer:
        `No. It is free with no paid tier or account. If you choose a cloud transcription model or use AI actions or AI summaries, your own ${CLOUD_PROVIDERS_OR} key is billed by that provider.`,
    },
  ],
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
        "The implementation and release documentation for VoiceToText’s shortcut, permissions, models, review flow, history, and recording features.",
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
      href: "/compare/best-dictation-apps-for-mac",
      title: "Best dictation apps for Mac",
      description: "Seven Mac dictation apps side by side on dictation, files, meetings, privacy, languages and price.",
    },
  ],
  ctaTitle: "You do not have to uninstall Apple Dictation.",
  ctaBody:
    "Give VoiceToText a different shortcut, dictate the same paragraph with both tools, and keep the workflow that makes fewer corrections on your Mac.",
  analyticsPlacement: "apple_alternative",
};

// ---------------------------------------------------------------------------
// Parakeet vs. Whisper: every number below comes from lib/app-facts.ts, the
// same catalog the app's Models pane prints, so the page and the app agree.
// Two kinds of fact come from elsewhere, checked 2026-11-13: parameter counts
// from the upstream model cards (NVIDIA: 600 million for parakeet-tdt-0.6b-v3;
// OpenAI's Whisper README: 1550 M for large, 809 M for turbo, "an optimized
// version of large-v3"), and the speed wording from the app's own model notes
// in ModelRegistry.swift ("Fastest on your Mac", "Noticeably slower than Turbo").
// The Apple answer follows Apple's Mac User Guide for macOS 27.

function werCell(model: ModelFact, benchmark: WerBenchmark): string {
  const figure = model.wer.find((wer) => wer.benchmark === benchmark);
  if (!figure) return "Not listed";
  return figure.estimate ? `≈${figure.percent}% (estimate)` : `${figure.percent}%`;
}

function roleCell(model: ModelFact): string {
  const tags = [
    model.isDefault ? "Default" : null,
    model.chip ? `“${model.chip}”${model.isLocal && model.chip === "Most accurate" ? " (local)" : ""}` : null,
  ].filter(Boolean);
  return tags.length ? `${tags.join(" · ")}. ${model.bestFor}` : model.bestFor;
}

const LOCAL = localModels();
const PARAKEET = LOCAL.find((m) => m.id === "parakeet-tdt-v3")!;
const LARGE_V3 = LOCAL.find((m) => m.id === "whisper-large-v3")!;
const TURBO = LOCAL.find((m) => m.id === "whisper-large-v3-turbo")!;
const TINY = LOCAL.find((m) => m.id === "whisper-tiny")!;
const GPT_TRANSCRIBE = modelById("openai-gpt-transcribe")!;
const SCRIBE = modelById("elevenlabs-scribe-v2-realtime")!;
const DIARIZE = modelById("openai-gpt-4o-transcribe-diarize")!;
const CHEAPEST_CLOUD = cheapestCloudModel();

const openAsr = (m: ModelFact) => werCell(m, "Open ASR Leaderboard");
const aaWer = (m: ModelFact) => werCell(m, "Artificial Analysis AA-WER");
/** Parakeet's AA-WER as a bare number, for prose that says "an estimated …%" itself. */
const PARAKEET_AA = PARAKEET.wer.find((wer) => wer.benchmark === "Artificial Analysis AA-WER")?.percent;
const size = (m: ModelFact) => formatDownloadSize(m) ?? "—";
/** "25" from "25 European languages". */
const languageCount = (m: ModelFact) => m.languagesInApp.match(/\d+/)?.[0] ?? m.languagesInApp;

export const whisperVsParakeetConfig: SeoLandingConfig = {
  path: "/whisper-vs-parakeet-mac",
  title: "Parakeet vs Whisper on Mac: TDT v3 vs Large v3 and Turbo",
  description: `Parakeet TDT v3 vs Whisper Large v3: ${openAsr(PARAKEET)} vs ${openAsr(LARGE_V3)} Open ASR WER, ≈${PARAKEET_AA}% vs ${aaWer(LARGE_V3)} AA-WER, ${languageCount(PARAKEET)} vs ${languageCount(LARGE_V3)} languages. Parakeet is faster; Whisper covers more.`,
  breadcrumb: "Parakeet vs Whisper on Mac",
  parent: { name: "Compare", path: "/compare" },
  eyebrow: "Local model guide",
  readingTime: "9 min",
  h1: "Parakeet vs Whisper on Mac: Parakeet TDT v3 compared with Whisper Large v3 and Turbo.",
  lead: `Parakeet TDT v3 is the faster, smaller choice for ${PARAKEET.languagesInApp}. Whisper Large v3 and Large v3 Turbo cover ${LARGE_V3.languagesInApp} and lead one of the two public benchmarks. VoiceToText runs all three on your Mac, offline after a one-time download.`,
  heroPoints: [
    "Two public WER benchmarks",
    `${languageCount(PARAKEET)} vs ${languageCount(LARGE_V3)} languages`,
    "All three run offline",
    "Test method included",
  ],
  summaryTitle: "Which should you use?",
  summary: (
    <>
      Start with Parakeet TDT v3 if you speak one of its {PARAKEET.languagesInApp}. It is VoiceToText’s
      default and, in the app’s words, the fastest model on your Mac; it is also the smallest download of the
      three ({size(PARAKEET)}, against {size(LARGE_V3)} for Whisper Large v3) and has the lowest Open ASR
      Leaderboard error rate: {openAsr(PARAKEET)}, against {openAsr(LARGE_V3)} for Large v3 and{" "}
      {openAsr(TURBO)} for Turbo. Choose Whisper for any other language, since it covers{" "}
      {LARGE_V3.languagesInApp}, or when Parakeet stumbles on your audio: on Artificial Analysis’s AA-WER,
      Large v3 scores {aaWer(LARGE_V3)} and Turbo {aaWer(TURBO)}, against an estimated {PARAKEET_AA}% for
      Parakeet. Of the two Whisper models, Turbo is the quicker one, and Large v3, noticeably slower, has the
      highest quality score of any local model ({formatQuality(LARGE_V3)}). None of these figures were measured
      on a Mac, so dictate the same minute of your own speech with each and keep the one that makes fewer
      meaning-changing mistakes.
    </>
  ),
  atAGlance: {
    title: "Six local models, by the numbers.",
    rowHeader: "Model",
    caption: `Third-party figures as the VoiceToText Models pane shows them (${CATALOG_SNAPSHOT}). Word error rate (WER): lower is better. Quality score: 1–10, higher is better.`,
    columns: [
      "Quality score",
      "Open ASR WER",
      "AA-WER",
      "Languages in VoiceToText",
      "Download (approx.)",
      "Role",
    ],
    rows: LOCAL.map((model) => ({
      label: model.name,
      cells: [
        formatQuality(model),
        openAsr(model),
        aaWer(model),
        model.languagesInApp,
        formatDownloadSize(model) ?? "—",
        roleCell(model),
      ],
    })),
    note: (
      <>
        {QUALITY_SCORE_SOURCES} {DOWNLOAD_SIZE_NOTE} The Models pane lists 99 languages for the Whisper
        models, which is the upstream model’s count; VoiceToText detects the language automatically.
        Artificial Analysis has not benchmarked Parakeet v3, so
        its AA-WER is the v2 model’s result carried over. Its Whisper figures come from hosted cloud versions,
        not from a Mac.
      </>
    ),
  },
  sections: [
    {
      id: "head-to-head",
      eyebrow: "Head to head",
      title: "Parakeet TDT v3 vs Whisper Large v3 and Large v3 Turbo.",
      intro: (
        <>
          The three models most comparisons are about: NVIDIA’s parakeet-tdt-0.6b-v3, often called Parakeet v3,
          against OpenAI’s largest Whisper and its faster Turbo variant. VoiceToText runs all three locally.
        </>
      ),
      cards: [
        {
          title: "Accuracy depends on the benchmark",
          body: `On the Open ASR Leaderboard, Parakeet TDT v3 has the lowest word error rate at ${openAsr(PARAKEET)}, ahead of Whisper Large v3 (${openAsr(LARGE_V3)}) and Turbo (${openAsr(TURBO)}). On Artificial Analysis’s AA-WER the order flips: Large v3 ${aaWer(LARGE_V3)}, Turbo ${aaWer(TURBO)}, Parakeet about ${PARAKEET_AA}%, a figure carried over from v2. Lower is better.`,
        },
        {
          title: `${languageCount(PARAKEET)} languages vs ${languageCount(LARGE_V3)}`,
          body: `Parakeet TDT v3 covers ${PARAKEET.languagesInApp}, English included. Whisper Large v3 and Turbo cover ${LARGE_V3.languagesInApp}. All three detect the language themselves; VoiceToText has no language picker.`,
        },
        {
          title: "0.6 billion parameters vs 1.55 billion",
          body: `NVIDIA lists 600 million parameters for Parakeet TDT v3, a ${size(PARAKEET)} download in the app. OpenAI lists 1,550 million for Whisper Large v3 (${size(LARGE_V3)}) and 809 million for Turbo (${size(TURBO)}).`,
        },
        {
          title: "Speed: Parakeet first, Large v3 last",
          body:
            "VoiceToText calls Parakeet the fastest model on your Mac and Large v3 noticeably slower than Turbo, which OpenAI describes as an optimized Large v3 with faster transcription and minimal loss of accuracy. The app publishes no timings, so time a few dictations on your own Mac.",
        },
      ],
      note: `Turbo or Large v3? Turbo scores ${formatQuality(TURBO)} in the app against ${formatQuality(LARGE_V3)} for Large v3 and is the quicker of the two, so it is the easier Whisper to live with. Move to Large v3 when Turbo misses words that matter.`,
    },
    {
      id: "parakeet",
      eyebrow: "Why start with Parakeet",
      title: "A responsive default is valuable when dictation happens dozens of times a day.",
      cards: [
        {
          title: "Designed for fast recognition",
          body:
            "NVIDIA describes Parakeet TDT as a fast speech-recognition family. In VoiceToText it is the default and carries the “Recommended” chip for everyday dictation.",
        },
        {
          title: "25 European languages, automatically",
          body:
            "NVIDIA lists Bulgarian, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish, French, German, Greek, Hungarian, Italian, Latvian, Lithuanian, Maltese, Polish, Portuguese, Romanian, Slovak, Slovenian, Spanish, Swedish, Russian and Ukrainian. There is no language setting to change: the model detects it.",
        },
        {
          title: "Punctuation and capitalization",
          body:
            "The v3 model writes punctuation and capitalization itself, so the text reads as prose without a separate cleanup pass.",
        },
        {
          title: "One clear starting point",
          body: `Parakeet starts downloading on first launch (${formatDownloadSize(PARAKEET)} in the app’s catalog). Dictate representative sentences, and move to Whisper only when a concrete problem appears.`,
        },
      ],
    },
    {
      id: "whisper",
      eyebrow: "Why choose Whisper",
      title: "Whisper gives you more sizes, and it covers 99 languages.",
      paragraphs: [
        <>
          OpenAI’s model card lists Tiny, Base, Small, Medium, Large and Turbo variants. VoiceToText offers
          Tiny, Base, Small, Large v3 and Large v3 Turbo, from {size(TINY)} for Tiny to {size(LARGE_V3)} for
          Large v3 in the app’s catalog. The smaller sizes suit a Mac short on space or memory; the larger
          ones are for when transcript quality matters more than turnaround.
        </>,
        <>
          Upstream, Whisper is multilingual and can translate speech into English. VoiceToText uses it to
          transcribe, not translate: there is no language picker, and the model detects the language itself,
          once per recording from its first speech, then keeps it, so a recording that switches language
          stays in the first one. Accuracy varies by language, strongest in English and other widely spoken
          ones, so test it on your own speech.
        </>,
        <>
          OpenAI also warns that performance is uneven across accents and that these weakly supervised models
          can produce text that was never spoken. Choose Whisper when you speak a language outside
          Parakeet’s 25, when you want to compare sizes, or when it handles your microphone, accent or
          vocabulary better. Large v3 has the
          app’s “Most accurate” chip among local models; keep a smaller size handy if it slows you down.
        </>,
      ],
    },
    {
      id: "benchmarks",
      eyebrow: "Read the numbers",
      title: "Why the two leaderboards disagree about Parakeet and Whisper.",
      paragraphs: [
        <>
          On Hugging Face’s Open ASR Leaderboard, Parakeet TDT v3 has the lowest error rate of the six local
          models at {openAsr(PARAKEET)}. On Artificial Analysis’s AA-WER, Whisper Large v3 ({aaWer(LARGE_V3)})
          and Turbo ({aaWer(TURBO)}) come out ahead of Parakeet’s estimated {PARAKEET_AA}%.
        </>,
        <>
          Both can be right. The Open ASR Leaderboard averages results over a set of public English test sets.
          AA-WER uses Artificial Analysis’s own mix, half of it its AgentTalk set and the rest cleaned
          VoxPopuli and Earnings22 audio. It measured Whisper on hosted cloud versions, and it hasn’t tested
          Parakeet v3 at all, so the Parakeet figure is v2’s result carried over. Different audio, text
          normalization and runtimes produce different orderings.
        </>,
        <>
          VoiceToText’s quality score uses AA-WER first and the Open ASR Leaderboard only where AA has no
          figure. That is why the app scores Whisper Large v3 at {formatQuality(LARGE_V3)} and Parakeet at{" "}
          {formatQuality(PARAKEET)} while recommending Parakeet as the default. Treat the score as a summary,
          not a verdict: none of these numbers were measured by VoiceToText, on a Mac, or on your voice.
        </>,
      ],
      note:
        "The app shows no speed numbers either. It describes Parakeet as the fastest model on your Mac and Large v3 as noticeably slower than Turbo, but only your own Mac can tell you how long each takes.",
    },
    {
      id: "families",
      eyebrow: "Understand the choice",
      title: "These are model families, not two fixed settings.",
      paragraphs: [
        <>
          Whisper is OpenAI’s open speech-recognition and speech-translation model family. Its official model
          card documents multiple sizes, multilingual models, and translation into English. VoiceToText ships
          five local sizes through WhisperKit: Tiny, Base, Small, Large v3 and Large v3 Turbo. That gives you an
          explicit storage, memory and accuracy tradeoff.
        </>,
        <>
          Parakeet is NVIDIA’s family of speech-recognition models built on a FastConformer encoder with CTC,
          RNN-T or TDT decoders. VoiceToText runs Parakeet TDT v3 (0.6B parameters) through FluidAudio.
          NVIDIA’s model card lists transcription with punctuation, capitalization and timestamps in 25
          European languages, with the language detected automatically.
        </>,
        <>
          The app wrapper matters too. VoiceToText runs converted, Apple-optimized versions, not the reference
          PyTorch or NeMo code from the upstream repositories. A benchmark run on other hardware with other
          decoding settings doesn’t transfer directly to one Mac app.
        </>,
      ],
    },
    {
      id: "cloud",
      eyebrow: "Beyond local",
      title: "When a cloud model is the better call.",
      intro: (
        <>
          VoiceToText also offers {countWord(cloudModels().length).toLowerCase()} optional cloud models. They
          send the audio to {CLOUD_PROVIDERS_OR} on your own API key and are billed per hour of audio, so they
          are not{" "}
          <Link href="/offline-speech-to-text-mac">offline</Link>. Four situations favor them.
        </>
      ),
      cards: [
        {
          title: `Highest quality score: ${GPT_TRANSCRIBE.name}`,
          body: `OpenAI’s ${GPT_TRANSCRIBE.name} tops the app’s quality scores at ${formatQuality(GPT_TRANSCRIBE)} (AA-WER ${aaWer(GPT_TRANSCRIBE)}) for ${formatPrice(GPT_TRANSCRIBE)}. It works for dictation, meetings and imported files.`,
        },
        {
          title: `Words as you speak: ${SCRIBE.name}`,
          body: `ElevenLabs’ ${SCRIBE.name} shows words one by one in the Large recording HUD while you talk, scores ${formatQuality(SCRIBE)}, covers ${SCRIBE.languagesInApp} and costs ${formatPrice(SCRIBE)}. Live models work for dictation only; local models show text when you stop.`,
        },
        {
          title: `Lowest cost: ${CHEAPEST_CLOUD.name} on ${CHEAPEST_CLOUD.provider}`,
          body: `At ${formatPrice(CHEAPEST_CLOUD)}, it is the cheapest cloud option, with a quality score of ${formatQuality(CHEAPEST_CLOUD)}.${CHEAPEST_CLOUD.priceNote ? ` ${CHEAPEST_CLOUD.priceNote}` : ""}`,
        },
        {
          title: "Other languages and speaker labels",
          body: `OpenAI models detect 99+ languages and ElevenLabs 90+, worth comparing with local Whisper for a language outside Parakeet’s 25. For meetings where you need to know who said what, ${DIARIZE.name} (${formatPrice(DIARIZE)}) labels speakers; no local model does.`,
        },
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
            "Record 60–90 seconds once, then open it in History and use Regenerate with each model. Every version stays side by side, so you compare the same audio rather than a new take.",
        },
        {
          title: "Include your hard words",
          body:
            "Say names, product terms, acronyms, numbers, commands, and a sentence with negation. These errors matter more than easy filler words.",
        },
        {
          title: "Score what affects work",
          body:
            "Count meaning-changing errors and correction time. Also note how long each model takes on the Mac you actually use; a GPU benchmark won’t tell you.",
        },
        {
          title: "Repeat in real conditions",
          body:
            "Try a quiet desk, a headset, a room microphone, and the accent or language mix you actually meet. One clean sample can hide the failure you care about.",
        },
      ],
      note: (
        <>
          For important transcripts, keep the recording and check the text against it. Neither family should
          be treated as authoritative for medical, legal, safety or other high-risk decisions. If you are
          still choosing an app rather than a model, <Link href="/compare">compare the Mac dictation apps</Link>;
          for prompts and code, see <Link href="/voice-to-text-for-coding">voice to text for coding</Link>.
        </>
      ),
    },
  ],
  comparison: {
    title: "Parakeet TDT v3 vs the Whisper family, in detail.",
    caption:
      "Model-family characteristics as they apply inside VoiceToText; exact behavior depends on the checkpoint and the app release.",
    columns: ["Parakeet TDT v3", "Whisper"],
    rows: [
      {
        label: "Practical role",
        cells: ["Default local model for regular dictation.", "Alternative family with five local sizes."],
      },
      {
        label: "Upstream developer",
        cells: ["NVIDIA.", "OpenAI."],
      },
      {
        label: "Choices in VoiceToText",
        cells: ["One option: Parakeet TDT v3.", "Large v3 Turbo, Large v3, Small, Base, and Tiny."],
      },
      {
        label: "Languages in VoiceToText",
        cells: [
          "25 European languages, detected automatically.",
          "99 languages, detected automatically once per recording.",
        ],
      },
      {
        label: "Published error rates",
        cells: [
          `Open ASR ${openAsr(PARAKEET)}; AA-WER ${aaWer(PARAKEET)}.`,
          `Large v3: Open ASR ${openAsr(LARGE_V3)}, AA-WER ${aaWer(LARGE_V3)}. Turbo: ${openAsr(TURBO)} and ${aaWer(TURBO)}.`,
        ],
      },
      {
        label: "Local implementation",
        cells: ["FluidAudio on Apple hardware.", "WhisperKit on Apple hardware."],
      },
      {
        label: "With the network off",
        cells: [
          "Loads and transcribes offline after its one-time download.",
          "Loads and transcribes offline after its one-time download.",
        ],
      },
      {
        label: "What can go wrong",
        cells: [
          "A language outside its 25, or vocabulary the model handles poorly.",
          "Weaker results in less common languages, resource cost on large sizes, uneven accent results, and possible invented text documented by OpenAI.",
        ],
      },
      {
        label: "Best test",
        cells: [
          "Compare correction time on frequent, short dictations.",
          "Regenerate one saved recording with each relevant size.",
        ],
      },
    ],
    note:
      "The error rates are third-party results on other hardware and datasets, shown as the app shows them. They are not VoiceToText measurements, so test on your own audio before you decide.",
  },
  faq: [
    {
      question: "Is Parakeet TDT v3 more accurate than Whisper Large v3?",
      answer: `It depends on the benchmark. On the Open ASR Leaderboard, Parakeet TDT v3 (${openAsr(PARAKEET)}) beats Whisper Large v3 (${openAsr(LARGE_V3)}). On Artificial Analysis AA-WER, Whisper Large v3 (${aaWer(LARGE_V3)}) beats Parakeet's estimated ${PARAKEET_AA}%. Test both on your own audio.`,
    },
    {
      question: "Should I use Whisper Large v3 or Large v3 Turbo?",
      answer: `Try Turbo first. OpenAI describes it as an optimized Large v3 with faster transcription and minimal loss of accuracy, and the app scores it ${formatQuality(TURBO)} against ${formatQuality(LARGE_V3)} for Large v3, which it calls noticeably slower than Turbo. Both cover ${LARGE_V3.languagesInApp} and run offline; switch to Large v3 if Turbo misses words you need.`,
    },
    {
      question: "Which model is faster on a Mac?",
      answer:
        "VoiceToText publishes no speed numbers. The app describes Parakeet TDT v3 as the fastest model on your Mac and Whisper Large v3 as noticeably slower than Large v3 Turbo. Time a few dictations on your own Mac to be sure.",
    },
    {
      question: "Apple speech vs Parakeet: which should I use on a Mac?",
      answer:
        "Apple's speech recognition is what built-in Mac Dictation uses: there is nothing to install, it enters text at the insertion point, and it takes spoken punctuation. Apple says Keyboard settings show whether general text Dictation is processed on your Mac rather than sent to Siri servers, and in macOS 27 Apple Intelligence adds an on-device model that improves spelling, punctuation and capitalization in English on Macs with M3 or later and at least 12 GB of memory. VoiceToText doesn't use Apple's engine, including the SpeechAnalyzer API apps can call on macOS 26 and later; its local models are Parakeet TDT v3 and Whisper, which run on your Mac after a one-time download. This page has no benchmark figure for Apple's engine, so dictate the same paragraph with both and keep the one you correct less.",
    },
    {
      question: "Can local Whisper in VoiceToText transcribe languages other than English?",
      answer:
        "Yes. The local Whisper models cover 99 languages and detect the one you speak automatically, once per recording from its first speech; there is no language picker. Accuracy varies by language, so test your own speech against Parakeet or a cloud model.",
    },
    {
      question: "How much disk space do the local models need?",
      answer: `The app's catalog lists downloads from ${size(TINY)} for Whisper Tiny to ${size(LARGE_V3)} for Whisper Large v3 and ${size(TURBO)} for Large v3 Turbo; Parakeet TDT v3, the default, is ${size(PARAKEET)}. The space a model takes once installed can differ. Each model downloads once and then runs fully offline.`,
    },
    {
      question: "Did VoiceToText run these accuracy tests?",
      answer:
        "No. The error rates come from the Open ASR Leaderboard and Artificial Analysis, and the app's 1–10 quality score is derived from them. None were measured on a Mac or on your voice.",
    },
  ],
  sources: [
    {
      label: "NVIDIA Parakeet TDT 0.6B v3 model card",
      href: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3",
      detail: "NVIDIA’s model card for the Parakeet version VoiceToText runs: its 25 languages, automatic language detection, and output features.",
    },
    {
      label: "Hugging Face Open ASR Leaderboard",
      href: "https://huggingface.co/spaces/hf-audio/open_asr_leaderboard",
      detail: "The public leaderboard behind the Open ASR word error rates in the table above.",
    },
    {
      label: "Artificial Analysis: Speech to Text",
      href: "https://artificialanalysis.ai/speech-to-text",
      detail: "The AA-WER leaderboard and its method: an audio-weighted mix of AgentTalk, VoxPopuli and Earnings22 test sets, run against hosted APIs.",
    },
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
        "The reference implementation and its table of model sizes with parameter counts, plus language behavior and approximate hardware tradeoffs in the upstream project.",
    },
    {
      label: "NVIDIA NeMo ASR checkpoints",
      href: "https://docs.nvidia.com/nemo/speech/nightly/asr/asr_checkpoints.html",
      detail:
        "NVIDIA’s checkpoint table for Parakeet variants, decoder type, tasks, languages, and model size.",
    },
    {
      label: "Apple: Dictate messages and documents on Mac",
      href: "https://support.apple.com/guide/mac-help/dictate-messages-and-documents-mh40584/mac",
      detail:
        "Apple’s guide to built-in Dictation, the basis of the Apple answer above: where to check on-device processing, and the on-device Apple Intelligence model in macOS 27.",
    },
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail:
        "The app’s source, including the WhisperKit and FluidAudio integrations, the model catalog the table is built from, and the speed notes the app shows for each model.",
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
