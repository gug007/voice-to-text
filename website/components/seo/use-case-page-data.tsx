import Link from "next/link";

import type { SeoLandingConfig } from "./seo-landing";

export const offlineSpeechToTextConfig: SeoLandingConfig = {
  path: "/offline-speech-to-text-mac",
  title: "Offline Speech to Text for Mac — Private, Free",
  description:
    "Run speech to text locally on an Apple Silicon Mac. Learn what stays offline, how to set it up, which model to choose, and where cloud features begin.",
  breadcrumb: "Offline speech to text for Mac",
  eyebrow: "Privacy guide",
  readingTime: "6 min",
  h1: "Offline speech to text on Mac, without sending your recordings away.",
  lead:
    "VoiceToText downloads a speech model to your Mac once and transcribes locally after that. With the default Parakeet model, you can dictate into any app, transcribe files and record meetings with the network off, and without uploading the audio anywhere.",
  heroPoints: [
    "Local model by default",
    "No app account",
    "Source on GitHub",
    "macOS 15+ · Apple Silicon",
  ],
  summaryTitle: "The short answer",
  summary: (
    <>
      With Parakeet, the default model, transcription runs on your Mac and works with Wi-Fi off. The app
      download, the first model download and the update check need the internet. Whisper models also
      transcribe on your Mac, but loading one needs a connection, so use Parakeet on a fully offline Mac. Audio
      leaves the Mac only if you choose an OpenAI or ElevenLabs cloud model. Transcript text leaves the Mac
      only if you run an AI action or generate an AI summary, and then it goes to OpenAI on your own key.
    </>
  ),
  sections: [
    {
      id: "what-offline-means",
      eyebrow: "Define the boundary",
      title: "“Offline” should describe the audio path, not make a blanket network claim.",
      intro:
        "A useful privacy answer names every point where the network can appear. That makes it possible to choose the right workflow instead of relying on a vague badge.",
      paragraphs: [
        <>
          In local mode, microphone or file audio is processed by a downloaded model on the Mac. The
          transcript is produced on-device, and there is nothing to upload it to: VoiceToText has no account,
          no first-party server and no analytics in the app.
        </>,
        <>
          With a local model and no API keys, the app makes two kinds of connection. It fetches models from
          Hugging Face, and it checks GitHub Releases for a new version at launch and every 24 hours. An update
          installs only when you click Install Update. Neither connection carries your audio or your
          transcripts.
        </>,
        <>
          <strong>For a fully offline Mac, use Parakeet.</strong> Parakeet, the default, works with the network
          off after its one-time download. Whisper models also transcribe on your Mac, and your audio never
          leaves it, but the current version contacts Hugging Face whenever it loads a Whisper model (after each
          launch), so loading one needs an internet connection.
        </>,
        <>
          Everything else is opt-in and tied to a key you paste in. A cloud transcription model (OpenAI or
          ElevenLabs) sends the audio to that provider, whether you use it for dictation, a meeting, a
          file import or a “Regenerate with” pass in History. AI actions in the review panel and AI
          summaries, action items or custom results on a recording send transcript text to OpenAI. Adding a
          key also sends one verification request to that provider.
        </>,
      ],
      note: (
        <>
          Practical test: once Parakeet has downloaded, quit and reopen VoiceToText with Wi-Fi off, make a
          short dictation, and confirm that transcription still completes. You can also read the public source
          or watch outbound connections with a network monitor.
        </>
      ),
    },
    {
      id: "setup",
      eyebrow: "Set it up",
      title: "A local dictation workflow in four deliberate steps.",
      cards: [
        {
          title: "Install the signed app",
          body:
            "Download the DMG from GitHub Releases, move VoiceToText to Applications, and open it. Current builds require macOS 15 or later and an Apple Silicon Mac.",
        },
        {
          title: "Let the default model download",
          body:
            "Parakeet TDT v3, the default, starts downloading from Hugging Face on first launch. With Parakeet, this is the one step that needs the internet. It covers English and 24 other European languages, detected automatically. The local Whisper sizes are an alternative for English: VoiceToText currently transcribes them in English only, and loading one needs a connection.",
        },
        {
          title: "Grant only the needed permissions",
          body:
            "Microphone captures speech. Accessibility is needed to start a recording and to paste at the cursor. Recording a meeting also needs Screen Recording, which is how macOS hands apps the system audio. The app records audio only, never the screen.",
        },
        {
          title: "Run the three-check local test",
          body: (
            <>
              Before sensitive work, check three things. In Settings → Models, a local model is selected
              (Parakeet if the Mac will be offline). In Settings → Conversations, the Transcription model is “Same as dictation” or another
              local model, because it controls meetings and file imports separately. When you regenerate a
              recording, pick a local model from the “Regenerate with” menu. For a strictly local session,
              also skip AI actions and AI insights.
            </>
          ),
        },
      ],
    },
    {
      id: "workflows",
      eyebrow: "Use it beyond a memo",
      title: "One local engine can serve short dictation, files, and long conversations.",
      paragraphs: [
        <>
          For everyday writing, put the cursor in Mail, Notes, a browser, chat, or a code editor. Press the
          global shortcut (⌥Space by default), speak, stop, review, and paste. The review step is useful when
          names, numbers or commands must be exact. You can turn review off to paste the moment you stop.
        </>,
        <>
          For existing audio or video, drop one file onto Conversations or choose Upload File…. Any format
          macOS can read works, such as MP3, M4A, WAV, AIFF, FLAC, MP4 or MOV. MKV, WebM and AVI don’t open.
          VoiceToText extracts the audio, transcribes it with the Conversations transcription model (local by
          default), and saves the transcript in History with an audio-only copy. The original file stays
          where it was, and History doesn’t keep the video. This suits confidential interviews or research
          recordings better than a browser uploader when policy forbids sending recordings to a third party.
        </>,
        <>
          For meetings, VoiceToText records your microphone and the Mac’s system audio together, with no bot
          joining the call; see <Link href="/meeting-recording">how meeting recording works</Link>. Local
          models don’t label speakers. Speaker labels come only from the cloud model GPT-4o Transcribe
          Diarize, which is not an offline option. Local transcription keeps the recording on the machine,
          but consent obligations don’t go away: recording laws and workplace rules vary, so tell
          participants and follow the rules that apply to the call.
        </>,
      ],
    },
    {
      id: "limits",
      eyebrow: "Know the tradeoffs",
      title: "Local processing gives control, but it is not automatically the best result for every recording.",
      cards: [
        {
          title: "Hardware matters",
          body:
            "Larger Whisper models use more storage, memory and processing time. A smaller model, or Parakeet, can feel better for rapid dictation on a Mac with less memory.",
        },
        {
          title: "Audio quality still matters",
          body:
            "Distance from the microphone, overlapping speakers, room noise and domain-specific names all change the transcript. Check important output against the recording, which History keeps.",
        },
        {
          title: "Languages depend on the model",
          body: (
            <>
              On the Mac, Parakeet covers 25 European languages automatically, and the local Whisper models
              transcribe English. The app has no language setting. Any other language needs a cloud model
              (OpenAI covers 99+ and ElevenLabs 90+, detected automatically), and cloud models are not
              offline. The <Link href="/whisper-vs-parakeet-mac">Whisper vs. Parakeet guide</Link> compares
              the six local models.
            </>
          ),
        },
        {
          title: "Local is not anonymous",
          body:
            "By default VoiceToText saves every dictation’s audio and transcript in History (~/Library/Application Support/VoiceToText/History). To stop saving dictations, turn off Save recordings in the History pane. Conversations and imports are always saved. History keeps the newest 200 recordings. Protect your user account, turn on FileVault, and delete sensitive recordings you no longer need.",
        },
      ],
      note: (
        <>
          Weighing local-first apps against cloud dictation services? The{" "}
          <Link href="/compare">comparison hub</Link> sorts the Mac dictation apps by where they process
          your audio.
        </>
      ),
    },
  ],
  comparison: {
    caption: "The choices available inside VoiceToText; no universal accuracy claim is implied.",
    columns: ["Local model", "Optional cloud model"],
    rows: [
      {
        label: "Audio processing",
        cells: ["Runs on the Mac after a one-time model download.", "Runs at OpenAI or ElevenLabs, sent directly from your Mac."],
      },
      {
        label: "Internet during transcription",
        cells: ["Not required. Loading a Whisper model needs a connection; Parakeet doesn’t.", "Required."],
      },
      {
        label: "Provider account",
        cells: ["No account or API key required.", "Your own provider API key, billed by the provider per hour of audio."],
      },
      {
        label: "Languages",
        cells: [
          "Parakeet: 25 European languages, automatic. Local Whisper: English.",
          "OpenAI 99+ or ElevenLabs 90+, detected automatically.",
        ],
      },
      {
        label: "Best fit",
        cells: [
          "Private or offline work, predictable control, and no usage billing.",
          "Words appearing live as you speak, speaker labels, other languages, or a hard recording you choose to send.",
        ],
      },
      {
        label: "AI actions and insights",
        cells: [
          "Optional either way: they send transcript text, not audio, to OpenAI on your key.",
          "Same: transcript text to OpenAI, on your key.",
        ],
      },
      {
        label: "What to verify",
        cells: [
          "The dictation model, the Conversations transcription model, History saving, and quality on your audio.",
          "Provider terms, retention controls, cost, and whether the audio is allowed to leave the device.",
        ],
      },
    ],
    note:
      "“Local” describes where transcription runs. It does not replace consent, retention, access-control or backup decisions.",
  },
  faq: [
    {
      question: "Does VoiceToText work with no internet connection?",
      answer:
        "Yes, with Parakeet, the default model, once it has downloaded: dictation, meeting recording and file transcription then work with the network off. Whisper models also transcribe on the Mac, but the current version contacts Hugging Face each time it loads one, so loading a Whisper model needs a connection. Cloud models, AI actions and AI insights need the internet.",
    },
    {
      question: "What does VoiceToText connect to when it runs locally?",
      answer:
        "With local models and no API keys, it downloads models from Hugging Face, checks with Hugging Face each time it loads a Whisper model, and checks GitHub Releases for updates at launch and every 24 hours. Updates install only when you confirm. The app has no account, analytics or first-party server.",
    },
    {
      question: "Are my dictations saved on the Mac?",
      answer:
        "Yes, by default. Each dictation's audio and transcript is saved in History on your Mac. Turn off Save recordings in the History pane to stop saving dictations. Conversations and imported files are always saved. History keeps the newest 200 recordings.",
    },
    {
      question: "Which languages work offline?",
      answer:
        "Parakeet TDT v3, the default, covers 25 European languages, detects them automatically and works fully offline. The local Whisper models currently transcribe English in VoiceToText. Other languages need an OpenAI or ElevenLabs cloud model, which sends the audio to that provider.",
    },
    {
      question: "Can I record meetings offline?",
      answer:
        "Yes, with Parakeet. Conversations records your microphone and system audio and transcribes the recording on the Mac when you stop, using a local model. Speaker labels are the exception: they need the cloud model GPT-4o Transcribe Diarize.",
    },
  ],
  sources: [
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail:
        "The public Swift source, installation notes, feature list and issue history for the app described on this page.",
    },
    {
      label: "VoiceToText releases",
      href: "https://github.com/gug007/voice-to-text/releases",
      detail:
        "Signed release downloads and version history. Review the current release notes before installing.",
    },
    {
      label: "NVIDIA Parakeet TDT 0.6B v3 model card",
      href: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3",
      detail:
        "NVIDIA’s documentation for the default local model, including its 25 supported languages and automatic language detection.",
    },
    {
      label: "OpenAI Whisper model card",
      href: "https://github.com/openai/whisper/blob/main/model-card.md",
      detail:
        "Primary documentation for Whisper’s model family, intended uses, and limitations such as uneven performance and possible hallucinations.",
    },
  ],
  related: [
    {
      href: "/whisper-vs-parakeet-mac",
      title: "Whisper vs. Parakeet on Mac",
      description: "Benchmark figures, languages and download sizes for the six local models.",
    },
    {
      href: "/meeting-recording",
      title: "Record and transcribe meetings",
      description: "Capture microphone and system audio without adding a bot to the call.",
    },
    {
      href: "/compare",
      title: "Compare Mac dictation apps",
      description: "Every VoiceToText comparison in one place, including local-first and cloud products.",
    },
  ],
  ctaTitle: "Try a complete dictation with Wi-Fi off.",
  ctaBody:
    "Let the default Parakeet model download once, disconnect, and test the whole record–transcribe–review–paste loop on your own Mac.",
  analyticsPlacement: "offline_speech",
};

export const codingVoiceToTextConfig: SeoLandingConfig = {
  path: "/voice-to-text-for-coding",
  title: "Voice to Text for Coding on Mac — Cursor, VS Code & AI",
  description:
    "Use voice to draft prompts, explain bugs, write comments, and capture implementation notes in Cursor, VS Code, terminals, and AI coding tools on Mac.",
  breadcrumb: "Voice to text for coding",
  eyebrow: "Developer workflow",
  readingTime: "6 min",
  h1: "Voice to text for coding: talk through intent, keep your hands on the hard parts.",
  lead:
    "Dictation is strongest for prompts, plans, bug reports, comments and review notes, not for spelling out every brace. VoiceToText pastes your reviewed speech into whatever coding tool has the cursor.",
  heroPoints: [
    "Cursor & VS Code",
    "Terminals & chat",
    "Local transcription",
    "Review before paste",
  ],
  summaryTitle: "Use voice for the semantic layer",
  summary: (
    <>
      Speak the outcome, constraints, evidence and acceptance criteria; type exact symbols and identifiers.
      That split avoids the most frustrating part of code dictation and makes long AI-agent prompts,
      pull-request notes and debugging narratives much quicker to capture. Dictate a long prompt in several
      passes with ⌘R, and if you want it restructured, the optional Improve prompt action does that on your
      own OpenAI key.
    </>
  ),
  sections: [
    {
      id: "best-tasks",
      eyebrow: "Start with high-leverage text",
      title: "The best coding dictation is usually prose that controls code.",
      intro:
        "A transcript does not have to be source code to move a software task forward. Modern coding work contains a large amount of natural-language context.",
      cards: [
        {
          title: "Agent and chat prompts",
          body:
            "Describe the change, files in scope, constraints, edge cases, and how to verify it. A complete spoken brief is more useful than a terse one-line request.",
        },
        {
          title: "Bug reproduction",
          body:
            "Narrate what you did, what you expected, what actually happened, and the exact environment while the failure is still visible.",
        },
        {
          title: "Comments and documentation",
          body:
            "Explain why a decision exists, summarize a public API, or capture migration guidance, then edit the transcript for identifiers and precision.",
        },
        {
          title: "Review and handoff notes",
          body:
            "Dictate PR feedback, test findings, stand-up notes, and a session handoff without switching away from the diff, terminal, or issue form.",
        },
      ],
    },
    {
      id: "prompt-pattern",
      eyebrow: "A repeatable pattern",
      title: "Speak prompts in five passes, then review once.",
      paragraphs: [
        <>
          Begin with the goal: “Add keyboard navigation to the command menu.” Follow with the relevant
          context: framework, component, current behavior, and files you already inspected. Then name the
          constraints: preserve public APIs, avoid a new dependency, or keep the feature accessible without
          JavaScript.
        </>,
        <>
          Next, dictate edge cases and acceptance checks. Mention empty states, focus restoration, reduced
          motion, error handling, and the commands or tests that should pass. End by defining the output you
          want from the agent: an implementation, a diagnosis only, or a short plan before any edits.
        </>,
        <>
          You don’t have to say it in one breath. Stop after a pass, and in the review panel press ⌘R
          (Resume) to record the next pass. It is inserted at the caret, so you can also click into the
          middle of the draft and add a missed constraint there. If a resumed take fails, the earlier text
          comes back.
        </>,
        <>
          Before pasting, correct paths, function names, issue numbers and negations. Those few tokens often
          carry more technical meaning than the rest of the prompt, and a speech model can’t guess a
          project-specific spelling it has never seen.
        </>,
      ],
      note: (
        <>
          Optional: turn on <strong>Improve prompt</strong> in Settings → Actions and add an OpenAI key. In
          the review panel, press its ⌘1–⌘9 shortcut and the transcript is rewritten as a structured prompt:
          goal first, numbered steps, identifiers in written form (<code>user_id</code>, camelCase), and every
          “do not / must / keep” constraint preserved. Undo steps back if you prefer your own wording. It
          sends the transcript text to OpenAI (gpt-5.5) and bills your key, so skip it for anything that must
          stay on the Mac.
        </>
      ),
    },
    {
      id: "workflow",
      eyebrow: "Keep it in the active tool",
      title: "Use the same shortcut in an editor, terminal, browser, or native app.",
      cards: [
        {
          title: "Place the cursor deliberately",
          body:
            "Click the exact chat box, issue field, comment or document location that should receive the text. VoiceToText pastes into the field that has focus, in any app where ⌘V pastes text.",
        },
        {
          title: "Speak naturally, without dictation commands",
          body: (
            <>
              Press ⌥Space (the default), speak in full sentences, and let the model punctuate. VoiceToText
              has no voice commands: saying “comma” or “new line” types the word, unless you run the optional
              Clean transcript or Fix grammar action. Built-in cleanup also puts a space after dots, so{" "}
              <code>package.json</code> can come out as “package. Json”.
            </>
          ),
        },
        {
          title: "Review technical tokens",
          body:
            "Check filenames, package names, flags, commands, URLs, versions, and words such as “not.” Edit them before they can steer an agent or a shell in the wrong direction.",
        },
        {
          title: "Paste, then type the syntax",
          body:
            "Press Return (or the dictation shortcut) to paste, and Shift+Return for a new line inside the panel. Add code fences, backticks, operators and exact snippets with the keyboard, or let the coding tool write the code from your prose.",
        },
        {
          title: "Trigger it from your tools",
          body: (
            <>
              VoiceToText answers a URL scheme: <code>open -g voicetotext://toggle</code> starts or stops
              dictation, and <code>start</code>, <code>stop</code> and <code>cancel</code> work the same way.
              Bind it to a Raycast script, a Shortcuts action or a Stream Deck key. The <code>-g</code> flag
              keeps your editor in front, so the text lands there.
            </>
          ),
        },
        {
          title: "Pick the model for the repo",
          body: (
            <>
              For private code, stay on a local model: Parakeet or Whisper. Local Whisper transcribes English;
              Parakeet also handles 24 other European languages. The{" "}
              <Link href="/whisper-vs-parakeet-mac">Whisper vs. Parakeet comparison</Link> has the benchmark
              numbers.
            </>
          ),
        },
      ],
    },
    {
      id: "safety",
      eyebrow: "Accuracy and safety",
      title: "Treat a transcript as draft input, especially near a shell.",
      paragraphs: [
        <>
          Don’t paste a dictated shell command and run it straight away. A single missing “not,” changed
          path or invented flag can turn a harmless request into a destructive one. Keep review on, paste
          into an editor or prompt box first, and read the final command before it runs.
        </>,
        <>
          Voice is also a poor way to enter secrets. Never dictate API keys, passwords, recovery codes or
          private tokens. Use a password manager or another secure input that keeps the secret out of a
          transcript and out of History.
        </>,
        <>
          For private repositories, choose a local model so the recording is transcribed on the Mac; the{" "}
          <Link href="/offline-speech-to-text-mac">offline guide</Link> lists the three settings to check.
          Remember that the destination can still be in the cloud: pasting a private prompt into a hosted AI
          tool sends the text under that tool’s terms, even if speech recognition itself was local.
        </>,
      ],
    },
    {
      id: "when-keyboard-wins",
      eyebrow: "Choose the right input",
      title: "Keep typing when token-level precision dominates.",
      cards: [
        {
          title: "Exact code",
          body:
            "Dense syntax, indentation, escaping, generics, regular expressions and short identifiers are usually faster and safer to type.",
        },
        {
          title: "Sensitive values",
          body:
            "Credentials and private keys should never enter a dictation. The paste goes through the clipboard: VoiceToText saves your previous clipboard and restores it about a quarter of a second later. By default, History also keeps each dictation’s audio and transcript.",
        },
        {
          title: "Noisy shared spaces",
          body:
            "A keyboard keeps things private and accurate when colleagues are talking, or when saying project details aloud would disturb people.",
        },
        {
          title: "Small edits",
          body:
            "Renaming one symbol or flipping a boolean is not a speech task. Reach for voice when the thought is longer than the edit.",
        },
      ],
      note: (
        <>
          Choosing a dictation app for coding? See how VoiceToText compares with{" "}
          <Link href="/wispr-flow-alternative">Wispr Flow</Link>, a cloud dictation app many developers use,
          or browse <Link href="/compare">every comparison</Link>.
        </>
      ),
    },
  ],
  comparison: {
    caption: "A practical division of labor for coding on a Mac.",
    columns: ["Dictate", "Type"],
    rows: [
      {
        label: "AI prompts",
        cells: ["Goals, context, constraints, examples, and acceptance criteria.", "Exact paths, commands, and code samples."],
      },
      {
        label: "Source code",
        cells: ["Comments, docstrings, and high-level pseudocode.", "Syntax, identifiers, operators, and indentation."],
      },
      {
        label: "Debugging",
        cells: ["Reproduction narrative and observations while the bug is visible.", "Logs, stack traces, hashes, and precise values."],
      },
      {
        label: "Code review",
        cells: ["Reasoning, risks, suggested behavior, and questions.", "Inline patches and token-level corrections."],
      },
      {
        label: "Terminal",
        cells: ["Explain the task to an agent or draft a command for review.", "Inspect and run the final command yourself."],
      },
    ],
    note:
      "The safest default is reviewed paste. Instant paste is convenient for low-risk prose, but technical tokens deserve a visual check.",
  },
  faq: [
    {
      question: "Does VoiceToText work in Cursor, VS Code and the terminal?",
      answer:
        "Yes. It pastes the reviewed text into whichever field has focus, using the clipboard and a ⌘V, so it works anywhere ⌘V pastes text: editors, AI chat panels, terminals and browsers. It needs Accessibility permission for this.",
    },
    {
      question: "Can I say “new line” or “open paren” to insert symbols?",
      answer:
        "No. VoiceToText has no voice commands, so spoken symbol names are typed as words. The optional Clean transcript and Fix grammar actions turn cues like “comma” or “new line” into formatting. Type code symbols yourself.",
    },
    {
      question: "Is there an AI action for coding prompts?",
      answer:
        "Yes, Improve prompt. It is off by default. Turn it on in Settings → Actions and add an OpenAI key, then press its ⌘1–⌘9 shortcut in the review panel. It rewrites the transcript as a structured prompt and sends the text to OpenAI on your key.",
    },
    {
      question: "Can I start dictation from Raycast, Shortcuts or a script?",
      answer:
        "Yes. Run open -g voicetotext://toggle to start or stop dictation; start, stop and cancel also exist. The -g flag keeps the current app in front, so the text lands there.",
    },
    {
      question: "Does my code or prompt leave the Mac?",
      answer:
        "Not for transcription with a local model. Audio is sent out only if you pick a cloud model, and text only if you run an AI action. The tool you paste into may still be a cloud service with its own terms.",
    },
  ],
  sources: [
    {
      label: "VoiceToText integration guide",
      href: "https://github.com/gug007/voice-to-text/blob/main/INTEGRATION.md",
      detail:
        "The project’s documentation for driving VoiceToText from other Mac apps with its voicetotext:// URL scheme.",
    },
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail:
        "Public source for the global shortcut, review panel, AI actions, local engines and paste behavior described here.",
    },
    {
      label: "Apple Voice Control guide",
      href: "https://support.apple.com/guide/mac-help/use-voice-control-commands-mh40719/mac",
      detail:
        "Apple’s documentation for a different workflow: navigating the Mac and dictating or editing text with Voice Control commands.",
    },
  ],
  related: [
    {
      href: "/wispr-flow-alternative",
      title: "VoiceToText vs Wispr Flow",
      description: "A popular cloud dictation app with developers, compared with a local-first alternative.",
    },
    {
      href: "/whisper-vs-parakeet-mac",
      title: "Whisper vs. Parakeet on Mac",
      description: "Choose the local model that fits the language and responsiveness of your development workflow.",
    },
    {
      href: "/compare",
      title: "Compare Mac dictation apps",
      description: "Every VoiceToText comparison in one place, with the tradeoffs spelled out.",
    },
  ],
  ctaTitle: "Try your next coding brief out loud.",
  ctaBody:
    "Open the prompt box you already use, speak the goal and constraints, check technical tokens, and paste the reviewed transcript.",
  analyticsPlacement: "coding_voice",
};
