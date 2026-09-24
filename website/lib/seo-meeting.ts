import { SITE_URL } from "./constants";
import { page } from "./pages";
import { PERSON_ID, SOFTWARE_ID, WEBSITE_ID, type FaqEntry } from "./seo-ids";

/* ---------- Meeting recording page ---------- */

export const MEETING_PATH = "/meeting-recording" as const;
export const MEETING_URL = `${SITE_URL}${MEETING_PATH}`;
export const MEETING_PUBLISHED = page(MEETING_PATH).published;
export const MEETING_UPDATED = page(MEETING_PATH).modified;

// One array feeds both the visible FAQ on /meeting-recording and the FAQPage
// JSON-LD below, so the two can never disagree. Keep it at 11 entries or fewer.
export const meetingFaqEntries: FaqEntry[] = [
  {
    question: "Can I record and transcribe meetings on my Mac for free?",
    answer:
      "Yes. VoiceToText is free, with source available on GitHub and no subscription, account, or per-minute fee. Transcribing with a local model costs nothing. Optional cloud models, speaker labels, and AI summaries are billed by the provider to your own API key. The same app also does hotkey dictation into any text field.",
  },
  {
    question: "Does it record the other participants, or just my microphone?",
    answer:
      "Both. VoiceToText captures your microphone and your Mac's system audio at the same time and mixes them into one recording, so the people on a Zoom, Google Meet, Microsoft Teams, FaceTime, Webex, or Discord call are recorded along with you. System audio comes through Apple's ScreenCaptureKit, so it works with any app that plays sound. There is no plugin, and no bot joins the call.",
  },
  {
    question: "Can VoiceToText identify and label different speakers?",
    answer:
      "Yes, with the optional cloud model GPT-4o Transcribe Diarize. Choose it as the Transcription model in Conversations, or regenerate an existing recording with it, and add your OpenAI API key. The transcript comes back as turns labeled Speaker 1, Speaker 2, and so on. Use Name speakers to replace the labels with real names; giving two labels the same name merges their turns. The audio is sent to OpenAI at a list price of $0.36 per hour, billed to your key. Local Parakeet and Whisper models do not separate speakers.",
  },
  {
    question: "Is meeting recording private? Does my audio stay on my Mac?",
    answer:
      "With a local model, yes. Conversations use the “Same as dictation” transcription model by default, which is the on-device Parakeet model unless you changed it, so the recording is transcribed on your Mac and the audio stays there. Audio goes to a provider only when a cloud model does the transcription: an OpenAI model you pick for Conversations, or a cloud dictation model while the setting is “Same as dictation”. AI summaries, action items, and custom prompts send the transcript text, not the audio, to OpenAI, and only when you ask for one.",
  },
  {
    question: "Which permissions does meeting recording need?",
    answer:
      "Two: Microphone, to record your voice, and Screen Recording, which is how macOS lets an app capture system audio through ScreenCaptureKit. VoiceToText never records the screen, only the audio. Accessibility is used only by dictation (the dictation shortcut, Esc to cancel, and pasting at the cursor), so recording a meeting doesn't need it. You can revoke either permission in System Settings → Privacy & Security.",
  },
  {
    question: "What happens with long meetings, or if the app crashes mid-recording?",
    answer:
      "Recordings longer than 12 minutes are transcribed in parts of about 10 minutes, each cut at the quietest nearby moment to avoid splitting words, with progress shown as it goes. The audio streams to disk while you record. If the app crashes, is force-quit, or the Mac loses power, the audio is repaired and filed into History on the next launch without a transcript; choose Regenerate on that recording to transcribe it. If transcription fails, the audio is still saved so you can try again. One exception: if macOS itself stops the audio capture during a recording, VoiceToText shows “Recording stopped” and that recording's audio is discarded.",
  },
  {
    question: "Can I transcribe an existing audio or video file?",
    answer:
      "Yes. In Conversations, click Upload File… or drag one audio or video file onto the pane. Files macOS can read work, such as MP3, M4A, WAV, AIFF, FLAC, MP4, and MOV; MKV, WebM, and AVI do not. VoiceToText extracts the audio and transcribes it with your Conversations transcription model, which is on-device by default, then saves it to History. History keeps the extracted audio, not the original video, and your original file is left untouched.",
  },
  {
    question: "Can I re-transcribe a recording with a more accurate model?",
    answer:
      "Yes. Every recording keeps its audio, so you can regenerate the transcript with any of the 15 models, for example switching from on-device Parakeet to OpenAI GPT Transcribe for a difficult recording. The new transcript becomes current and the earlier one is kept beside it, so you can compare them and remove the one you don't want. Existing summaries and action items are kept and marked as out of date, with a button to regenerate them.",
  },
  {
    question: "Can it summarize meetings and pull out action items?",
    answer:
      "Yes, once you add an OpenAI API key. From the sparkles menu on any recording you can generate a Summary, an Action Items checklist, or up to three results from your own prompt, such as meeting minutes or a follow-up email; conversation rows also show Summary, Action items, and Custom buttons. Each action item is a task with an owner and a due date only when someone actually said them. You can tick items off and copy the list as a Markdown checklist. These run on OpenAI's gpt-5.5 with your key and send the transcript text, including speaker names, to OpenAI. Transcription itself can still happen on your Mac.",
  },
  {
    question: "Can I start recording from any app?",
    answer:
      "Yes. Set a Conversation shortcut in Settings → Shortcut (there is no default key), then press it in any app to start recording and press it again to stop and transcribe. You can also choose Start Conversation Recording from the menu bar, which shows a running clock, or click Start Recording in Conversations. VoiceToText doesn't detect meetings or start recording by itself. There is no pause: Stop & Transcribe ends the recording, and Cancel deletes it without a transcript. Your voice is recorded from the Mac's default input, which you choose in System Settings → Sound.",
  },
  {
    question: "Can I search old transcripts?",
    answer:
      "Yes. The History pane has a Search transcripts field. It matches words in transcripts and their earlier versions, summaries, action items and owners, custom results, speaker names, model names, and dates, ignoring case and accents. History keeps your newest 200 recordings. Dictations and conversations share that limit and favorites are not exempt, so the oldest recordings are deleted, audio included, once you pass it.",
  },
];

export const meetingFaqPageJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "@id": `${MEETING_URL}#faq-page`,
  url: `${MEETING_URL}#faq`,
  isPartOf: { "@id": `${MEETING_URL}#webpage` },
  mainEntity: meetingFaqEntries.map(({ question, answer }) => ({
    "@type": "Question",
    name: question,
    acceptedAnswer: { "@type": "Answer", text: answer },
  })),
} as const;

export const meetingPageJsonLd = {
  "@context": "https://schema.org",
  "@type": "WebPage",
  "@id": `${MEETING_URL}#webpage`,
  name: "Record and transcribe meetings on Mac",
  description:
    "Free meeting recorder for Mac with source available on GitHub. Records microphone and system audio together with no bot in the call, transcribes on-device by default, and offers optional cloud speaker labels, AI summaries, and action-item checklists using your own OpenAI key.",
  url: MEETING_URL,
  datePublished: MEETING_PUBLISHED,
  dateModified: MEETING_UPDATED,
  isPartOf: { "@id": WEBSITE_ID },
  about: { "@id": SOFTWARE_ID },
  mainEntity: { "@id": SOFTWARE_ID },
  author: {
    "@id": PERSON_ID,
  },
  breadcrumb: { "@id": `${MEETING_URL}#breadcrumb` },
  primaryImageOfPage: {
    "@type": "ImageObject",
    url: `${MEETING_URL}/opengraph-image`,
    width: 1200,
    height: 630,
  },
  inLanguage: "en",
} as const;

export const meetingBreadcrumbJsonLd = {
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "@id": `${MEETING_URL}#breadcrumb`,
  itemListElement: [
    { "@type": "ListItem", position: 1, name: "Home", item: `${SITE_URL}/` },
    { "@type": "ListItem", position: 2, name: "Meeting recording", item: MEETING_URL },
  ],
} as const;
