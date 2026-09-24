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
  /**
   * ISO date this row was last re-checked against the vendor's own pages (or,
   * for VoiceToText, the app source). Falls back to the page's sourcesReviewed.
   */
  reviewed?: string;
  /** This site's dedicated head-to-head page, when there is one. */
  comparePath?: string;
};

export const products: Product[] = [
  {
    id: "voicetotext",
    name: "VoiceToText",
    label: "Best free local bundle",
    verdict:
      "The strongest no-cost fit when you want Mac dictation with reviewed paste, plus meeting recording, file import and a searchable history, in one app.",
    wins:
      "Free, no account, source on GitHub, a first-class review-before-paste workflow, and bot-free meeting recording with optional AI summaries and action items on your own key.",
    tradeoff:
      "Mac-only and Apple Silicon only, no cross-device sync or team controls, no voice commands, and speaker labels only through an optional cloud model.",
    dictation:
      "System-wide hotkey (⌥Space by default); review, then paste. Local models transcribe when you stop; three optional streaming cloud models show text as you speak, word by word or phrase by phrase.",
    files:
      "Imports one audio or video file at a time in formats macOS can read (not MKV, WebM or AVI). History keeps the transcript and an extracted audio-only copy, not the original video.",
    meetings:
      "Records microphone plus system audio without a bot. Optional AI summaries, action-item checklists and custom prompts on your OpenAI key; searchable local history. Speaker labels need the cloud model GPT-4o Transcribe Diarize.",
    correction:
      "Not yet timed. Edit the complete transcript before paste, add a take at the caret with ⌘R, or turn review off for instant paste. Opt-in AI actions (⌘1–⌘9) run on your OpenAI key.",
    privacy:
      "Parakeet and Whisper run on-device. An OpenAI or ElevenLabs model sends audio to that provider with your key; AI actions and summaries send transcript text to OpenAI.",
    languages:
      "Model-dependent: Parakeet (local, default) covers 25 European languages; local Whisper currently transcribes English; optional cloud models detect 90–99+ automatically.",
    price:
      "Free, no paid tier. Your own OpenAI or ElevenLabs key is billed for cloud transcription, AI actions and AI summaries.",
    sourceHref: "https://github.com/gug007/voice-to-text",
    reviewed: "2026-09-23",
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
    comparePath: "/apple-dictation-alternative",
  },
  {
    id: "wispr-flow",
    name: "Wispr Flow",
    label: "Best managed cloud workflow",
    verdict:
      "The strongest cross-device and enterprise fit, with polished dictation plus the richest integrated meeting intelligence in this set.",
    wins:
      "Mac, Windows, iPhone, and Android; a Notetaker with named speakers, summaries and cross-meeting search; team controls and compliance options.",
    tradeoff:
      "Transcription is cloud-only and needs an account. Notetaker runs on Mac and Windows and depends on Dictation Cloud Storage.",
    dictation:
      "System-wide cloud dictation with auto punctuation, filler removal, backtracking, dictionary, snippets and styles.",
    files: "A general audio/video file-import workflow was not found in current official app documentation; not tested.",
    meetings:
      "Notetaker (Mac and Windows) captures audio on the device without a visible bot; cloud transcripts with named speakers, summaries, action items, and search across meetings.",
    correction:
      "Not yet timed. A personal dictionary that learns your spellings, snippets, styles, and spoken backtracking (“at 2… actually 3”).",
    privacy:
      "Cloud transcription. “Improve the model for everyone” controls training; “Dictation Cloud Storage” separately controls server storage. Zero-retention dictation needs both off; Notetaker and AI summaries rely on cloud storage.",
    languages: "100+ for dictation; Notetaker transcribes 21 languages.",
    price: "Free plan (2,000 words a week on desktop); Pro $15/user/month or $12 billed annually; Growth and Enterprise for teams.",
    sourceHref: "https://wisprflow.ai/features",
    reviewed: "2026-09-23",
    comparePath: "/wispr-flow-alternative",
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
      "System-wide on Mac, Windows, iOS and Android; local or cloud speech plus context-aware modes and optional rewriting.",
    files: "Imports common audio/video formats and applies the active mode's transcription and formatting pipeline.",
    meetings: "Records meeting-app audio locally without a bot; supports file transcription and optional speaker separation.",
    correction:
      "Not yet timed. Inspect raw and processed output in History, re-run another mode, and use vocabulary or deterministic replacements.",
    privacy:
      "Local speech models keep audio on-device. Cloud models process through Superwhisper's service; Mac can also use a local LLM for rewriting.",
    languages: "Model-dependent: many Whisper/cloud choices cover 100+; individual local models may cover fewer.",
    price: "Free tier; Pro $8.49/month, $84.99/year, or $249.99 lifetime.",
    sourceHref: "https://superwhisper.com/models",
    comparePath: "/superwhisper-alternative",
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
      "Records the mic locally, with system-audio recording and speaker recognition on Pro; detects supported meeting apps. Verify beta behavior on critical calls.",
    correction:
      "Not yet timed. Full transcript editor, find/replace rules, AI prompts, synchronized playback, and local Ollama/LM Studio options.",
    privacy:
      "Local Whisper/Parakeet transcription and speaker identification by default. Cloud transcription, translation, or hosted AI sends data to the chosen provider.",
    languages: "100 languages documented across multilingual local and cloud models.",
    price: "Free tier; Pro is a one-time license with lifetime updates, listed at €64 on macwhisper.com (€65 at Gumroad checkout).",
    sourceHref: "https://www.macwhisper.com/",
    comparePath: "/macwhisper-alternative",
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
      ["Pricing", "https://wisprflow.ai/pricing"],
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
