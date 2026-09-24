// Product facts the site repeats in several places — the home Models section,
// /whisper-vs-parakeet-mac, llms.txt and the README. Each value was checked
// against the app source for the release named in CATALOG_SNAPSHOT:
//   VoiceToText/Engine/ModelRegistry.swift      catalog order, prices, WER, sizes, languages
//   VoiceToText/Engine/ModelQualityScore.swift  the 1–10 quality formula
//   VoiceToText/Settings/ModelsSettingsView.swift  chips and the LIVE badge
//   VoiceToText/Actions/DictationAction.swift   built-in AI actions
//   VoiceToText/Engine/WhisperKitEngine.swift   Whisper model loading (network)
//   VoiceToText/Engine/OpenAIRealtimeEngine.swift, ElevenLabsRealtimeEngine.swift  live text
// When the app's catalog changes, update this file and bump CATALOG_SNAPSHOT.

export const CATALOG_SNAPSHOT = "September 2026 · VoiceToText v0.0.57";

export const APP_REQUIREMENTS = {
  minMacOS: "15.0",
  os: "macOS 15.0 or later",
  processor: "Apple Silicon (M1 or newer)",
  /** The shipped binary is arm64 only. Say "Apple Silicon only", not a reason. */
  architecture: "arm64",
  short: "macOS 15.0+ · Apple Silicon",
} as const;

export type ModelProvider = "On this Mac" | "OpenAI" | "ElevenLabs";
export type WerBenchmark = "Artificial Analysis AA-WER" | "Open ASR Leaderboard";
export type ModelChip = "Recommended" | "Most accurate" | "Fastest";
export type LiveTextCadence = "word by word" | "phrase by phrase";

export type WerFigure = {
  benchmark: WerBenchmark;
  /** Word error rate in percent; lower is better. */
  percent: number;
  /** Carried over from a sibling model rather than measured on this one. */
  estimate: boolean;
  note?: string;
};

export type ModelFact = {
  /** The app's catalog id. */
  id: string;
  /** Name as the Models pane shows it, without the "(Provider)" suffix. */
  name: string;
  provider: ModelProvider;
  isLocal: boolean;
  /** The dictation model on a fresh install. */
  isDefault: boolean;
  /** Shows the LIVE badge: a streaming model, dictation only. */
  live: boolean;
  /** Words appear in the HUD while you speak. False for GPT Realtime Whisper, which commits when you stop. */
  showsLiveText: boolean;
  /**
   * How live text arrives, for models with `showsLiveText`. ElevenLabs streams
   * partial words; OpenAI's server-VAD models transcribe each phrase after a
   * short pause (silence_duration_ms 500 in OpenAIRealtimeEngine.swift).
   */
  liveTextCadence?: LiveTextCadence;
  /**
   * Loads and runs with the network off once downloaded. False for local
   * Whisper: every load (after each launch) asks Hugging Face for the model's
   * file list first, with no offline fallback. Always false for cloud models.
   */
  worksOffline: boolean;
  /** Can transcribe Conversations recordings and imported files (live models are excluded there). */
  conversations: boolean;
  /** Labels speakers (Speaker 1, Speaker 2…). */
  diarize: boolean;
  /**
   * What the model covers inside VoiceToText. Local Whisper is "English" even
   * though the upstream model family is multilingual: the app prefills the
   * English language token and has no language picker.
   */
  languagesInApp: string;
  /** Provider list price per hour of audio, billed to the user's own key. 0 for local models. */
  pricePerHourUSD: number;
  /** The 1–10 Quality score the Models pane prints. */
  quality: number;
  /** The pane prefixes the score with "≈": it rests on indirect evidence. */
  qualityApprox: boolean;
  wer: WerFigure[];
  /** Catalog download estimate in MB (local only). Real on-disk size can be larger. */
  approxDownloadMB?: number;
  /** The editorial chip on the model's row, if any (at most one). */
  chip?: ModelChip;
  /** One plain-language line on when to pick it. */
  bestFor: string;
};

const AA = "Artificial Analysis AA-WER" as const;
const OPEN_ASR = "Open ASR Leaderboard" as const;

/** All 15 models in the app's catalog order: 6 local, then 9 cloud. */
export const MODEL_CATALOG: readonly ModelFact[] = [
  {
    id: "parakeet-tdt-v3",
    name: "Parakeet TDT v3",
    provider: "On this Mac",
    isLocal: true,
    isDefault: true,
    live: false,
    showsLiveText: false,
    worksOffline: true,
    conversations: true,
    diarize: false,
    languagesInApp: "25 European languages",
    pricePerHourUSD: 0,
    quality: 7.4,
    qualityApprox: true,
    wer: [
      {
        benchmark: AA,
        percent: 6.4,
        estimate: true,
        note: "Artificial Analysis has not benchmarked v3; this is its predecessor Parakeet TDT 0.6B v2's figure.",
      },
      { benchmark: OPEN_ASR, percent: 6.32, estimate: false },
    ],
    approxDownloadMB: 470,
    chip: "Recommended",
    bestFor: "Everyday dictation on your Mac, in English and 24 other European languages.",
  },
  {
    id: "whisper-large-v3-turbo",
    name: "Whisper Large v3 Turbo",
    provider: "On this Mac",
    isLocal: true,
    isDefault: false,
    live: false,
    showsLiveText: false,
    worksOffline: false,
    conversations: true,
    diarize: false,
    languagesInApp: "English",
    pricePerHourUSD: 0,
    quality: 7.5,
    qualityApprox: false,
    wer: [
      { benchmark: OPEN_ASR, percent: 7.75, estimate: false },
      { benchmark: AA, percent: 4.6, estimate: false, note: "Best-host figure (Groq)." },
    ],
    approxDownloadMB: 632,
    bestFor: "English on your Mac with Whisper, quicker than Large v3.",
  },
  {
    id: "whisper-large-v3",
    name: "Whisper Large v3",
    provider: "On this Mac",
    isLocal: true,
    isDefault: false,
    live: false,
    showsLiveText: false,
    worksOffline: false,
    conversations: true,
    diarize: false,
    languagesInApp: "English",
    pricePerHourUSD: 0,
    quality: 8.0,
    qualityApprox: false,
    wer: [
      { benchmark: OPEN_ASR, percent: 7.44, estimate: false },
      { benchmark: AA, percent: 4.1, estimate: false, note: "Best-host figure (fal.ai)." },
    ],
    approxDownloadMB: 626,
    chip: "Most accurate",
    bestFor: "The most accurate English that stays on your Mac, if you can wait a little longer.",
  },
  {
    id: "whisper-small",
    name: "Whisper Small",
    provider: "On this Mac",
    isLocal: true,
    isDefault: false,
    live: false,
    showsLiveText: false,
    worksOffline: false,
    conversations: true,
    diarize: false,
    languagesInApp: "English",
    pricePerHourUSD: 0,
    quality: 7.4,
    qualityApprox: true,
    wer: [{ benchmark: OPEN_ASR, percent: 8.59, estimate: false }],
    approxDownloadMB: 244,
    bestFor: "English on a Mac short on disk space, with more mistakes.",
  },
  {
    id: "whisper-base",
    name: "Whisper Base",
    provider: "On this Mac",
    isLocal: true,
    isDefault: false,
    live: false,
    showsLiveText: false,
    worksOffline: false,
    conversations: true,
    diarize: false,
    languagesInApp: "English",
    pricePerHourUSD: 0,
    quality: 6.6,
    qualityApprox: true,
    wer: [{ benchmark: OPEN_ASR, percent: 10.32, estimate: false }],
    approxDownloadMB: 77,
    bestFor: "Slow Macs where a small download matters more than accuracy.",
  },
  {
    id: "whisper-tiny",
    name: "Whisper Tiny",
    provider: "On this Mac",
    isLocal: true,
    isDefault: false,
    live: false,
    showsLiveText: false,
    worksOffline: false,
    conversations: true,
    diarize: false,
    languagesInApp: "English",
    pricePerHourUSD: 0,
    quality: 5.6,
    qualityApprox: true,
    wer: [{ benchmark: OPEN_ASR, percent: 12.81, estimate: false }],
    approxDownloadMB: 39,
    bestFor: "Testing your setup. Too many mistakes for daily use.",
  },
  {
    id: "elevenlabs-scribe-v2-realtime",
    name: "Scribe v2 Realtime",
    provider: "ElevenLabs",
    isLocal: false,
    isDefault: false,
    live: true,
    showsLiveText: true,
    liveTextCadence: "word by word",
    worksOffline: false,
    conversations: false,
    diarize: false,
    languagesInApp: "90+ languages",
    pricePerHourUSD: 0.39,
    quality: 8.6,
    qualityApprox: false,
    wer: [{ benchmark: AA, percent: 3.6, estimate: false, note: "AA-WER Streaming, final transcript." }],
    chip: "Fastest",
    bestFor: "Live dictation in 90+ languages, with text appearing word by word as you speak.",
  },
  {
    id: "openai-gpt-live-transcribe",
    name: "GPT Live Transcribe",
    provider: "OpenAI",
    isLocal: false,
    isDefault: false,
    live: true,
    showsLiveText: true,
    liveTextCadence: "phrase by phrase",
    worksOffline: false,
    conversations: false,
    diarize: false,
    languagesInApp: "99+ languages",
    pricePerHourUSD: 1.02,
    quality: 8.2,
    qualityApprox: false,
    wer: [{ benchmark: AA, percent: 3.9, estimate: false, note: "AA-WER Streaming, final transcript." }],
    bestFor: "Live dictation with OpenAI's newest streaming model; text appears phrase by phrase, after each short pause.",
  },
  {
    id: "openai-gpt-realtime-whisper",
    name: "GPT Realtime Whisper",
    provider: "OpenAI",
    isLocal: false,
    isDefault: false,
    live: true,
    showsLiveText: false,
    worksOffline: false,
    conversations: false,
    diarize: false,
    languagesInApp: "99+ languages",
    pricePerHourUSD: 1.02,
    quality: 7.2,
    qualityApprox: false,
    wer: [
      {
        benchmark: AA,
        percent: 4.9,
        estimate: false,
        note: "AA-WER Streaming, final transcript (7.5% at first partial).",
      },
    ],
    bestFor: "Low-latency OpenAI dictation; the text appears only when you stop, not while you speak.",
  },
  {
    id: "openai-gpt-4o-transcribe-realtime",
    name: "GPT-4o Transcribe Realtime",
    provider: "OpenAI",
    isLocal: false,
    isDefault: false,
    live: true,
    showsLiveText: true,
    liveTextCadence: "phrase by phrase",
    worksOffline: false,
    conversations: false,
    diarize: false,
    languagesInApp: "99+ languages",
    pricePerHourUSD: 0.36,
    quality: 8.1,
    qualityApprox: true,
    wer: [
      {
        benchmark: AA,
        percent: 4.0,
        estimate: true,
        note: "Not on the streaming leaderboard; carried over from GPT-4o Transcribe's batch score.",
      },
    ],
    bestFor: "Live OpenAI dictation at about a third of GPT Live Transcribe's price; text appears phrase by phrase, after each short pause.",
  },
  {
    id: "openai-gpt-transcribe",
    name: "GPT Transcribe",
    provider: "OpenAI",
    isLocal: false,
    isDefault: false,
    live: false,
    showsLiveText: false,
    worksOffline: false,
    conversations: true,
    diarize: false,
    languagesInApp: "99+ languages",
    pricePerHourUSD: 0.27,
    quality: 8.9,
    qualityApprox: false,
    wer: [{ benchmark: AA, percent: 3.3, estimate: false }],
    chip: "Most accurate",
    bestFor: "The highest quality score in the catalog, for dictation, meetings and files.",
  },
  {
    id: "openai-gpt-4o-transcribe",
    name: "GPT-4o Transcribe",
    provider: "OpenAI",
    isLocal: false,
    isDefault: false,
    live: false,
    showsLiveText: false,
    worksOffline: false,
    conversations: true,
    diarize: false,
    languagesInApp: "99+ languages",
    pricePerHourUSD: 0.36,
    quality: 8.1,
    qualityApprox: false,
    wer: [{ benchmark: AA, percent: 4.0, estimate: false }],
    bestFor: "Accurate cloud transcription; GPT Transcribe now scores higher for less.",
  },
  {
    id: "openai-gpt-4o-transcribe-diarize",
    name: "GPT-4o Transcribe Diarize",
    provider: "OpenAI",
    isLocal: false,
    isDefault: false,
    live: false,
    showsLiveText: false,
    worksOffline: false,
    conversations: true,
    diarize: true,
    languagesInApp: "99+ languages",
    pricePerHourUSD: 0.36,
    quality: 8.1,
    qualityApprox: true,
    wer: [
      {
        benchmark: AA,
        percent: 4.0,
        estimate: true,
        note: "Not independently benchmarked; OpenAI calls it roughly comparable to GPT-4o Transcribe, whose score this is.",
      },
    ],
    bestFor: "Meetings where you need to know who said what: it labels speakers.",
  },
  {
    id: "openai-gpt-4o-mini-transcribe",
    name: "GPT-4o Mini Transcribe",
    provider: "OpenAI",
    isLocal: false,
    isDefault: false,
    live: false,
    showsLiveText: false,
    worksOffline: false,
    conversations: true,
    diarize: false,
    languagesInApp: "99+ languages",
    pricePerHourUSD: 0.18,
    quality: 7.6,
    qualityApprox: false,
    wer: [{ benchmark: AA, percent: 4.5, estimate: false }],
    bestFor: "The lowest-cost cloud option, nearly as accurate as GPT-4o Transcribe.",
  },
  {
    id: "openai-whisper-1",
    name: "Whisper-1",
    provider: "OpenAI",
    isLocal: false,
    isDefault: false,
    live: false,
    showsLiveText: false,
    worksOffline: false,
    conversations: true,
    diarize: false,
    languagesInApp: "99 languages",
    pricePerHourUSD: 0.36,
    quality: 8.0,
    qualityApprox: false,
    wer: [
      {
        benchmark: AA,
        percent: 4.1,
        estimate: false,
        note: "Listed by Artificial Analysis as Whisper Large v2 (OpenAI).",
      },
    ],
    bestFor: "OpenAI's older hosted Whisper; newer OpenAI models score as well or better for the same price or less.",
  },
];

export const QUALITY_SCORE_SOURCES =
  "Quality scores (1–10) are the ones the app's Models pane shows. They are derived from third-party published word error rates — Artificial Analysis AA-WER first, the Hugging Face Open ASR Leaderboard where Artificial Analysis has no figure — on a log scale anchored so Whisper Large v3 scores 8.0. \"≈\" marks a score built from indirect evidence. VoiceToText does not run its own accuracy tests.";

export const DOWNLOAD_SIZE_NOTE =
  "Download sizes are the app's catalog estimates; the space a model takes on disk can be larger (Whisper Large v3 is about 1.6 GB once installed).";

/**
 * The offline caveat, worded once for every page that needs it in full.
 * Parakeet (FluidAudio) loads from disk once downloaded. WhisperKitEngine.prepare
 * calls WhisperKit.download on every load, which asks the Hugging Face API for
 * the file list before touching the local copy, so it fails with no connection.
 */
export const WHISPER_OFFLINE_NOTE =
  "Parakeet, the default, works with the network off after its one-time download. Whisper models also transcribe on your Mac, and your audio never leaves it, but the current version contacts Hugging Face whenever it loads a Whisper model (after each launch), so loading one needs an internet connection. For a fully offline Mac, use Parakeet.";

/** The six built-in AI actions in the app's order. All start switched off. */
export const BUILT_IN_ACTIONS = [
  "Clean transcript",
  "To English",
  "Improve prompt",
  "Fix grammar",
  "Summarize",
  "Essentials only",
] as const;

export type BuiltInAction = (typeof BUILT_IN_ACTIONS)[number];

/** The OpenAI model AI actions and AI insights run on, with the user's own key. */
export const AI_TEXT_MODEL = "gpt-5.5";

export const localModels = (): ModelFact[] => MODEL_CATALOG.filter((m) => m.isLocal);
export const cloudModels = (): ModelFact[] => MODEL_CATALOG.filter((m) => !m.isLocal);
export const liveModels = (): ModelFact[] => MODEL_CATALOG.filter((m) => m.live);
/** Names of the live models whose text appears at the given cadence while you speak. */
export const liveTextModelNames = (cadence: LiveTextCadence): string[] =>
  MODEL_CATALOG.filter((m) => m.live && m.showsLiveText && m.liveTextCadence === cadence).map((m) => m.name);
/** "A and B", "A, B and C". */
export function joinNames(names: readonly string[]): string {
  return names.length < 2 ? (names[0] ?? "") : `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
}
/** Live models that show nothing until you stop (GPT Realtime Whisper). */
export const liveOnStopModelNames = (): string[] =>
  MODEL_CATALOG.filter((m) => m.live && !m.showsLiveText).map((m) => m.name);
export const defaultModel = (): ModelFact => MODEL_CATALOG.find((m) => m.isDefault) ?? MODEL_CATALOG[0];
export const modelById = (id: string): ModelFact | undefined => MODEL_CATALOG.find((m) => m.id === id);

/** "Free" for local models, otherwise "$0.27/hr" as the Models pane prints it. */
export function formatPrice(model: Pick<ModelFact, "pricePerHourUSD">): string {
  return model.pricePerHourUSD === 0 ? "Free" : `$${model.pricePerHourUSD.toFixed(2)}/hr`;
}

/** "8.9" or "≈7.4", as the Models pane prints the score. */
export function formatQuality(model: Pick<ModelFact, "quality" | "qualityApprox">): string {
  return `${model.qualityApprox ? "≈" : ""}${model.quality.toFixed(1)}`;
}

/** "470 MB" style catalog estimate, or undefined for cloud models. */
export function formatDownloadSize(model: Pick<ModelFact, "approxDownloadMB">): string | undefined {
  return model.approxDownloadMB === undefined ? undefined : `~${model.approxDownloadMB} MB`;
}
