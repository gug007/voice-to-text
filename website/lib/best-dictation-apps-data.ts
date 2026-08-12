export type ProductId =
  | "voicetotext"
  | "apple-dictation"
  | "wispr-flow"
  | "superwhisper"
  | "macwhisper"
  | "aqua-voice"
  | "voiceink";

export type Product = {
  id: ProductId;
  name: string;
  label: string;
  verdict: string;
  wins: string;
  tradeoff: string;
  dictation: string;
  files: string;
  meetings: string;
  correction: string;
  privacy: string;
  languages: string;
  price: string;
  sourceHref: string;
};

export const REVIEW_DATE = "2026-08-12";

export const products: Product[] = [
  {
    id: "voicetotext",
    name: "VoiceToText",
    label: "Best free local bundle",
    verdict:
      "The strongest no-cost fit when you want Mac dictation, reviewed paste, file import, and local meeting capture in one small app.",
    wins:
      "Free, no app account, source available on GitHub, and a first-class review-before-paste workflow.",
    tradeoff:
      "Mac-only, Apple-silicon-only, no cross-device sync, no enterprise controls, and local meetings do not label speakers.",
    dictation:
      "System-wide hotkey; buffered local dictation by default, with optional cloud realtime models.",
    files: "Imports audio and video formats macOS can read; keeps transcript and media in local History.",
    meetings:
      "Captures microphone plus system audio without a bot. Local transcription is unlabeled; OpenAI diarization is optional and cloud-based.",
    correction:
      "Not yet timed. Edit the complete transcript before paste, or disable review for instant paste; optional AI actions are separate.",
    privacy:
      "Parakeet and Whisper run on-device. Choosing OpenAI or ElevenLabs sends audio to that provider with your key; AI actions send text to OpenAI.",
    languages: "Model-dependent: Parakeet lists 25 European languages; local Whisper options list 99.",
    price: "Free. No paid tier; provider charges apply only when you choose a BYOK cloud model.",
    sourceHref: "https://github.com/gug007/voice-to-text",
  },
  {
    id: "apple-dictation",
    name: "Apple Dictation",
    label: "Best built-in option",
    verdict:
      "Start here if quick cursor insertion is enough. It is already on the Mac, costs nothing extra, and has the deepest OS integration.",
    wins:
      "No install, account, or separate updater—and Apple silicon users can keep typing while they speak.",
    tradeoff:
      "Standard Dictation is not a file-transcription library or meeting recorder, and processing behavior varies by language and settings.",
    dictation: "Built into macOS; inserts at the cursor and supports configurable shortcuts and multiple languages.",
    files: "No general audio/video file-import workflow in standard Dictation.",
    meetings: "No dedicated meeting capture, speaker labeling, transcript library, or meeting summary workflow.",
    correction:
      "Not yet timed. Type while speaking on Apple silicon and choose alternatives for words macOS marks as ambiguous.",
    privacy:
      "Check Keyboard settings for the selected language: macOS states whether general Dictation is processed on-device. Improvement sharing is a separate opt-in.",
    languages: "Broad locale support, but Dictation, on-device processing, punctuation, and emoji each cover different subsets.",
    price: "Included with macOS.",
    sourceHref: "https://support.apple.com/guide/mac-help/use-dictation-mh40584/26/mac/26",
  },
  {
    id: "wispr-flow",
    name: "Wispr Flow",
    label: "Best managed cloud workflow",
    verdict:
      "The strongest cross-device and enterprise fit, with polished dictation plus the richest integrated meeting intelligence in this set.",
    wins:
      "Mac, Windows, iPhone, and Android; named-speaker meetings, live catch-up, summaries, search, team controls, and compliance options.",
    tradeoff:
      "Transcription is cloud-only. Meeting Notetaker is currently Mac and English only, and it requires Cloud Sync.",
    dictation:
      "System-wide cloud dictation with formatting, filler removal, backtracking, commands, and up to 20-minute desktop sessions.",
    files: "A general audio/video file-import workflow was not found in current official app documentation; not tested.",
    meetings:
      "Mac Notetaker captures on-device without a visible bot, then provides live transcripts, named speakers, summaries, Q&A, and meeting search.",
    correction:
      "Not yet timed. Dictionary, deterministic replacements, edit learning, spoken backtracking, commands, and selected-text workflows.",
    privacy:
      "Cloud transcription. Privacy Mode controls training; Cloud Sync separately controls storage. Zero-retention dictation needs both configured, while Notetaker requires sync.",
    languages: "100+ for dictation; current Notetaker is English only. Code-switching has documented limits.",
    price: "Free plan; Pro $15/month or $12/month billed annually; Enterprise is quote-based.",
    sourceHref: "https://wisprflow.ai/features",
  },
  {
    id: "superwhisper",
    name: "Superwhisper",
    label: "Best model flexibility",
    verdict:
      "The broadest model playground: local and cloud speech models, optional local or cloud rewriting, files, and meetings across several platforms.",
    wins:
      "The widest combined speech/language-model catalog here, including a fully local transcription-and-rewrite path on Mac.",
    tradeoff:
      "The many modes and model combinations add setup decisions, and privacy depends on both the speech and post-processing model selected.",
    dictation:
      "System-wide on Mac, Windows, and iOS; local or cloud speech plus context-aware modes and optional rewriting.",
    files: "Imports common audio/video formats and applies the active mode's transcription and formatting pipeline.",
    meetings: "Records meeting-app audio locally without a bot; supports file transcription and optional speaker separation.",
    correction:
      "Not yet timed. Inspect raw and processed output in History, re-run another mode, and use vocabulary or deterministic replacements.",
    privacy:
      "Local speech models keep audio on-device. Cloud models process through Superwhisper's service; Mac can also use a local LLM for rewriting.",
    languages: "Model-dependent: many Whisper/cloud choices cover 100+; individual local models may cover fewer.",
    price: "Free tier; Pro $8.49/month, $84.99/year, or $249.99 lifetime.",
    sourceHref: "https://superwhisper.com/models",
  },
  {
    id: "macwhisper",
    name: "MacWhisper",
    label: "Best for files",
    verdict:
      "The clear specialist for a serious file-transcription desk: batch queues, watch folders, subtitles, rich exports, YouTube, speakers, and a CLI.",
    wins:
      "No other product in this set documents a deeper end-to-end file workflow or as many production export and automation options.",
    tradeoff:
      "System-wide dictation and automatic meeting detection require the direct-download edition; older meeting docs still mark auto-detection beta.",
    dictation:
      "System-wide in the direct-download build, with optional grammar cleanup and app-specific prompts on Pro.",
    files:
      "Drag-and-drop, batch, watch folders, media URLs, subtitles, many exports, speaker output, recursive folders, and structured CLI JSON.",
    meetings:
      "Records mic/system audio locally, detects supported meeting apps, and offers speaker recognition; verify beta behavior on critical calls.",
    correction:
      "Not yet timed. Full transcript editor, find/replace rules, AI prompts, synchronized playback, and local Ollama/LM Studio options.",
    privacy:
      "Local Whisper/Parakeet transcription and speaker identification by default. Cloud transcription, translation, or hosted AI sends data to the chosen provider.",
    languages: "100 languages documented across multilingual local and cloud models.",
    price: "Free tier; Pro is currently listed at €64 once with lifetime updates.",
    sourceHref: "https://www.macwhisper.com/",
  },
  {
    id: "aqua-voice",
    name: "Aqua Voice",
    label: "Best voice correction",
    verdict:
      "The most direct correction experience: select text in any app, say the change, iterate, and undo by voice.",
    wins:
      "Selection-based Edit Mode, polished realtime output, and a technical-vocabulary-focused model at a relatively low subscription price.",
    tradeoff:
      "Cloud-only, requires an account, and no dedicated desktop file or meeting workflow is documented.",
    dictation:
      "System-wide on Mac and Windows, with streaming/refinement, context, custom instructions, and an optional realtime tier.",
    files:
      "No desktop app file-import workflow documented or tested. Aqua's separate developer API is not counted as an app feature.",
    meetings: "No dedicated desktop meeting recorder, speaker workflow, or meeting library documented or tested.",
    correction:
      "Not yet timed. Select text, speak a change, replace it in place, stack edits, and undo by voice; also offers dictionary and replacements.",
    privacy:
      "Audio is processed in the cloud; there is no offline mode. Privacy Mode changes transcript retention/training behavior, not the processing location.",
    languages: "49 with auto-detection. Free Starter uses the legacy engine; Pro includes Aqua's Avalon model.",
    price: "1,000 lifetime free words; Pro $10 monthly or $8/month annually; Max is shown at $24/month annually.",
    sourceHref: "https://aquavoice.com/mac",
  },
  {
    id: "voiceink",
    name: "VoiceInk",
    label: "Best licensed source control",
    verdict:
      "The strongest user-control option: GPLv3 source, local models, app/site modes, BYOK cloud providers, and shell automation.",
    wins:
      "A real open-source license, deep local customization, queued files, and a low one-time price for the supported binary.",
    tradeoff:
      "Apple-silicon-only, no dedicated meeting recorder or diarization workflow documented, and language reach depends on the chosen model.",
    dictation:
      "Native Mac dictation with local Parakeet, Whisper, and Apple models; optional BYOK cloud models and context-aware modes.",
    files: "Queues many audio/video formats through the same mode, formatting, replacement, and enhancement pipeline.",
    meetings: "No dedicated microphone-plus-system-audio meeting recorder or diarization workflow documented or tested.",
    correction:
      "Not yet timed. Replacements, optional AI enhancement, selected-text rewriting, and retry with another model or mode.",
    privacy:
      "Local by default with no VoiceInk transcript-storage server. Optional cloud transcription/enhancement and context are explicit selections.",
    languages: "Model-dependent; no single count is meaningful without naming the selected local or cloud engine.",
    price: "$29 lifetime for one Mac, $49 for two, or $69 for three; GPLv3 source can be built locally.",
    sourceHref: "https://tryvoiceink.com/",
  },
];

export const sourceGroups = [
  {
    name: "VoiceToText",
    links: [
      ["Source and current feature documentation", "https://github.com/gug007/voice-to-text"],
    ],
  },
  {
    name: "Apple Dictation",
    links: [
      ["Mac Dictation guide", "https://support.apple.com/guide/mac-help/use-dictation-mh40584/26/mac/26"],
      ["macOS feature availability", "https://www.apple.com/uk/macos/feature-availability/"],
      ["Improve Siri & Dictation", "https://support.apple.com/en-us/127070"],
    ],
  },
  {
    name: "Wispr Flow",
    links: [
      ["Features", "https://wisprflow.ai/features"],
      ["Notetaker", "https://wisprflow.ai/notetaker"],
      ["Privacy", "https://wisprflow.ai/privacy"],
      ["Data controls", "https://docs.wisprflow.ai/articles/9609615338-private-cloud-sync-and-data-sharing-preferences-in-wispr-flow"],
      ["Pricing", "https://wisprflow.ai/business"],
    ],
  },
  {
    name: "Superwhisper",
    links: [
      ["Models and processing paths", "https://superwhisper.com/models"],
      ["File transcription", "https://superwhisper.com/docs/get-started/transcribe-files"],
      ["Meeting transcription", "https://superwhisper.com/meeting-transcription"],
      ["Pricing", "https://superwhisper.com/vs/wispr-flow/pricing"],
    ],
  },
  {
    name: "MacWhisper",
    links: [
      ["Product and pricing", "https://www.macwhisper.com/"],
      ["Privacy paths", "https://docs.macwhisper.com/article/52-keeping-transcriptions-private"],
      ["Meeting recording", "https://docs.macwhisper.com/article/30-record-meetings"],
      ["Command-line tool", "https://docs.macwhisper.com/article/57-macwhisper-command-line-tool"],
    ],
  },
  {
    name: "Aqua Voice",
    links: [
      ["Mac features and pricing", "https://aquavoice.com/mac"],
      ["FAQ, languages, and privacy summary", "https://aquavoice.com/info/faq"],
      ["Edit Mode", "https://aquavoice.com/guide/edit-mode"],
      ["Privacy policy", "https://aquavoice.com/info/privacy"],
    ],
  },
  {
    name: "VoiceInk",
    links: [
      ["Product and pricing", "https://tryvoiceink.com/"],
      ["Privacy", "https://tryvoiceink.com/privacy"],
      ["File transcription", "https://tryvoiceink.com/docs/transcribe-audio-files"],
      ["GPLv3 source", "https://github.com/Beingpax/VoiceInk"],
    ],
  },
] as const;
