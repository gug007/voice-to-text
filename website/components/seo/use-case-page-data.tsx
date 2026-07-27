import type { SeoLandingConfig } from "./seo-landing";

export const offlineSpeechToTextConfig: SeoLandingConfig = {
  path: "/offline-speech-to-text-mac",
  title: "Offline Speech to Text for Mac — Private, Free",
  description:
    "Run speech to text locally on an Apple Silicon Mac. Learn what stays offline, how to set it up, which model to choose, and where cloud features begin.",
  breadcrumb: "Offline speech to text for Mac",
  eyebrow: "Privacy guide",
  readingTime: "7 min",
  h1: "Offline speech to text on Mac, without sending your recordings away.",
  lead:
    "VoiceToText downloads a speech model to your Mac and transcribes locally after that. You can dictate into any app, transcribe files, and record meetings without uploading the audio when a local model is selected.",
  heroPoints: [
    "Local models by default",
    "No app account",
    "Source on GitHub",
    "macOS 15+ · Apple Silicon",
  ],
  summaryTitle: "The short answer",
  summary: (
    <>
      Choose Parakeet or Whisper in VoiceToText and the actual transcription runs on your Mac. The initial
      app and model downloads need an internet connection, and the app checks GitHub for updates. Audio is
      sent off-device only when you deliberately select an optional cloud transcription model or run an AI
      transcript action with your own provider key.
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
          transcript is produced on-device and the app does not need to upload that recording to a
          VoiceToText server—there is no VoiceToText account or first-party transcription service.
        </>,
        <>
          A new installation still needs to download the app and a model. VoiceToText also checks GitHub
          Releases for updates. Those connections are different from sending the content of a dictation or
          meeting to a transcription provider.
        </>,
        <>
          Cloud models remain available as an explicit choice. If you select one, the audio goes directly to
          that provider under the API key you supply. AI cleanup actions likewise require a provider. For a
          strictly local session, stay on Parakeet or Whisper and do the final edit yourself.
        </>,
      ],
      note: (
        <>
          Practical test: disconnect Wi-Fi after the model has downloaded, make a short dictation, and confirm
          that transcription still completes. You can also inspect the public source or monitor outbound
          connections with a network utility.
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
            "Download the DMG from GitHub Releases, move VoiceToText to Applications, and open it. Current builds require macOS 15 or later on Apple Silicon.",
        },
        {
          title: "Download one local model",
          body:
            "Start with Parakeet for a responsive English workflow or choose a Whisper size when multilingual coverage or a different speed-and-quality tradeoff matters.",
        },
        {
          title: "Grant only the needed permissions",
          body:
            "Microphone captures speech. Accessibility lets the app paste at the focused cursor. Meeting capture separately uses Screen Recording permission to receive system audio.",
        },
        {
          title: "Confirm the selected engine",
          body:
            "Before sensitive work, check Settings → Models and make sure a local Parakeet or Whisper engine—not an OpenAI or ElevenLabs option—is active.",
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
          global shortcut, speak, stop, review, and paste. The review step is useful when names, numbers, or
          commands must be exact; instant paste is available when speed matters more.
        </>,
        <>
          For existing audio or video, import the file from Conversations. VoiceToText extracts its audio,
          runs the chosen local model, and stores the transcript in the on-device history. That is a better
          fit for confidential interviews or research recordings than a browser uploader when organizational
          policy forbids sending recordings to a third party.
        </>,
        <>
          For meetings, VoiceToText can capture the microphone and Mac system audio together. Local
          transcription keeps the recording on the machine, but consent obligations do not disappear:
          recording laws and workplace rules vary, so tell participants and follow the rules that apply to
          the call.
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
            "Larger Whisper models use more storage, memory, and processing time. A smaller model or Parakeet can feel better for rapid dictation on a memory-constrained Mac.",
        },
        {
          title: "Audio quality still matters",
          body:
            "Distance from the microphone, overlapping speakers, room noise, and domain-specific names can all change the transcript. Review important output against the recording.",
        },
        {
          title: "Languages differ by model",
          body:
            "Do not assume every engine covers the same languages equally. Use a representative sample in your language and compare models before committing to a long recording.",
        },
        {
          title: "Local is not anonymous",
          body:
            "Transcripts and recordings stored on the Mac are still data. Protect the user account, enable disk encryption, and delete sensitive history when it is no longer needed.",
        },
      ],
    },
  ],
  comparison: {
    caption: "The choices available inside VoiceToText; no universal accuracy claim is implied.",
    columns: ["Local model", "Optional cloud model"],
    rows: [
      {
        label: "Audio processing",
        cells: ["Runs on the Mac after the model download.", "Runs at the selected external provider."],
      },
      {
        label: "Internet during transcription",
        cells: ["Not required.", "Required."],
      },
      {
        label: "Provider account",
        cells: ["No account or API key required.", "Your own provider API key is required."],
      },
      {
        label: "Best fit",
        cells: [
          "Private or offline work, predictable control, and no usage billing.",
          "A specific cloud capability, realtime output, or a difficult recording you choose to send.",
        ],
      },
      {
        label: "What to verify",
        cells: [
          "Active model, local storage policy, and transcript quality on your audio.",
          "Provider terms, retention controls, cost, and whether the audio is permitted to leave the device.",
        ],
      },
    ],
    note:
      "“Local” describes where transcription runs. It does not replace consent, retention, access-control, or backup decisions.",
  },
  sources: [
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail:
        "The public Swift source, installation notes, feature list, and issue history for the app described on this page.",
    },
    {
      label: "VoiceToText releases",
      href: "https://github.com/gug007/voice-to-text/releases",
      detail:
        "Signed release downloads and version history. Review the current release notes before installing.",
    },
    {
      label: "OpenAI Whisper model card",
      href: "https://github.com/openai/whisper/blob/main/model-card.md",
      detail:
        "Primary documentation for Whisper’s model family, intended uses, multilingual training, and limitations such as uneven performance and possible hallucinations.",
    },
  ],
  related: [
    {
      href: "/whisper-vs-parakeet-mac",
      title: "Whisper vs. Parakeet on Mac",
      description: "Choose a local engine based on language, responsiveness, and your own representative audio.",
    },
    {
      href: "/how-to-use-voice-to-text-on-mac",
      title: "How to use voice to text on Mac",
      description: "Install the app, grant permissions, choose a shortcut, and dictate into any text field.",
    },
    {
      href: "/meeting-recording",
      title: "Record and transcribe meetings",
      description: "Capture microphone and system audio without adding a bot to the call.",
    },
  ],
  ctaTitle: "Try a complete dictation with Wi-Fi off.",
  ctaBody:
    "Download a local model once, disconnect, and test the whole record–transcribe–review–paste loop on your own Mac.",
  analyticsPlacement: "offline_speech",
};

export const codingVoiceToTextConfig: SeoLandingConfig = {
  path: "/voice-to-text-for-coding",
  title: "Voice to Text for Coding on Mac — Cursor, VS Code & AI",
  description:
    "Use voice to draft prompts, explain bugs, write comments, and capture implementation notes in Cursor, VS Code, terminals, and AI coding tools on Mac.",
  breadcrumb: "Voice to text for coding",
  eyebrow: "Developer workflow",
  readingTime: "8 min",
  h1: "Voice to text for coding: talk through intent, keep your hands on the hard parts.",
  lead:
    "Dictation is strongest for prompts, plans, bug reports, comments, and review notes—not for spelling every brace. VoiceToText pastes reviewed speech into the coding tool already under your cursor.",
  heroPoints: [
    "Cursor & VS Code",
    "Terminals & chat",
    "Local transcription",
    "Review before paste",
  ],
  summaryTitle: "Use voice for the semantic layer",
  summary: (
    <>
      Speak the outcome, constraints, evidence, and acceptance criteria; type exact symbols and identifiers.
      That division avoids the most frustrating part of code dictation while making detailed AI-agent prompts,
      pull-request notes, and debugging narratives much faster to capture.
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
          want from the agent—implementation, diagnosis only, or a small plan before edits.
        </>,
        <>
          Stop and use the review panel before pasting. Correct paths, function names, issue numbers, and
          negations. Those few tokens often carry more technical meaning than the rest of the prompt, and a
          speech model cannot infer a project-specific spelling it has never seen.
        </>,
      ],
      note:
        "A useful spoken prompt template: Goal → context → constraints → edge cases → verification. Pause between sections; do not try to dictate Markdown formatting while you are still deciding what to say.",
    },
    {
      id: "workflow",
      eyebrow: "Keep it in the active tool",
      title: "Use the same shortcut in an editor, terminal, browser, or native app.",
      cards: [
        {
          title: "Place the cursor deliberately",
          body:
            "Click the exact chat box, issue field, comment, or document location that should receive the text. VoiceToText returns the transcript to the focused field.",
        },
        {
          title: "Record in a natural sentence",
          body:
            "Press Option+Space by default, or use your custom shortcut. Say complete thoughts and name punctuation only when the literal character matters.",
        },
        {
          title: "Review technical tokens",
          body:
            "Check filenames, package names, flags, commands, URLs, versions, and words such as “not.” Edit them before they can steer an agent or shell in the wrong direction.",
        },
        {
          title: "Paste, then type the syntax",
          body:
            "Press Return to paste. Add code fences, backticks, operators, and exact snippets with the keyboard or let the coding tool generate code from the prose.",
        },
      ],
    },
    {
      id: "safety",
      eyebrow: "Accuracy and safety",
      title: "Treat a transcript as draft input, especially near a shell.",
      paragraphs: [
        <>
          Do not auto-paste dictated shell commands and immediately run them. A single missing “not,” changed
          path, or invented flag can turn a harmless request into a destructive operation. Keep review enabled,
          paste into an editor or prompt box first, and read the final command before execution.
        </>,
        <>
          Voice is also a poor way to enter secrets. Never dictate API keys, passwords, recovery codes, or
          private tokens. Use a password manager or secure input flow that does not expose the secret in a
          transcript or local history.
        </>,
        <>
          For private repositories, choose a local Parakeet or Whisper model so the recording is transcribed on
          the Mac. Remember that the destination can still be cloud-based: pasting a private prompt into a
          hosted AI tool sends the text under that tool’s terms, even if speech recognition itself was local.
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
            "Dense syntax, indentation, escaping, generics, regular expressions, and short identifiers are usually faster and safer with a keyboard.",
        },
        {
          title: "Sensitive values",
          body:
            "Credentials and private keys should never enter a dictation transcript, review panel, clipboard, or speech history.",
        },
        {
          title: "Noisy shared spaces",
          body:
            "A keyboard preserves privacy and accuracy when colleagues are talking or when speaking project details aloud would be disruptive.",
        },
        {
          title: "Small edits",
          body:
            "Renaming one symbol or changing a boolean is not a speech task. Reach for voice when the thought is longer than the edit.",
        },
      ],
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
        cells: ["Explain the task to an agent or draft a command for review.", "Inspect and execute the final command yourself."],
      },
    ],
    note:
      "The safest default is reviewed paste. Instant paste is convenient for low-risk prose, but technical tokens deserve a visual check.",
  },
  sources: [
    {
      label: "VoiceToText integration guide",
      href: "https://github.com/gug007/voice-to-text/blob/main/INTEGRATION.md",
      detail:
        "The project’s primary documentation for invoking VoiceToText from other Mac apps with its URL scheme.",
    },
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail:
        "Public source for the global shortcut, review flow, local engines, and paste behavior described here.",
    },
    {
      label: "Apple Voice Control guide",
      href: "https://support.apple.com/guide/mac-help/use-voice-control-commands-mh40719/mac",
      detail:
        "Apple’s primary documentation for a different workflow: navigating the Mac and dictating or editing text with Voice Control commands.",
    },
  ],
  related: [
    {
      href: "/offline-speech-to-text-mac",
      title: "Offline speech to text on Mac",
      description: "Understand which parts of dictation stay on-device and when an optional cloud service begins.",
    },
    {
      href: "/whisper-vs-parakeet-mac",
      title: "Whisper vs. Parakeet on Mac",
      description: "Choose the local model that fits the language and responsiveness of your development workflow.",
    },
    {
      href: "/how-to-use-voice-to-text-on-mac",
      title: "Mac voice-to-text setup",
      description: "Configure permissions, a global shortcut, review-before-paste, and local models.",
    },
  ],
  ctaTitle: "Try your next coding brief out loud.",
  ctaBody:
    "Open the prompt box you already use, speak the goal and constraints, check technical tokens, and paste the reviewed transcript.",
  analyticsPlacement: "coding_voice",
};
