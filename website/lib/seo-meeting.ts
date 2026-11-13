import { AI_TEXT_MODEL, MICROPHONE_SETTING, MODEL_CATALOG, type ModelFact } from "./app-facts";
import { SITE_URL } from "./constants";
import { page } from "./pages";
import { PERSON_ID, SOFTWARE_ID, WEBSITE_ID, type FaqEntry } from "./seo-ids";

/* ---------- Meeting recording page ---------- */

export const MEETING_PATH = "/meeting-recording" as const;
export const MEETING_URL = `${SITE_URL}${MEETING_PATH}`;
export const MEETING_PUBLISHED = page(MEETING_PATH).published;
export const MEETING_UPDATED = page(MEETING_PATH).modified;

/* ---------- Facts the meeting pages share ---------- */

function requireModel(model: ModelFact | undefined, what: string): ModelFact {
  if (!model) throw new Error(`MODEL_CATALOG has no ${what}`);
  return model;
}

/** The one model that labels speakers (GPT-4o Transcribe Diarize). */
export const DIARIZE_MODEL = requireModel(MODEL_CATALOG.find((m) => m.diarize), "diarizing model");

/** Cloud models that can transcribe a conversation or an imported file (live models can't). */
export const CONVERSATION_CLOUD_MODELS: readonly ModelFact[] = MODEL_CATALOG.filter(
  (m) => !m.isLocal && m.conversations,
);

/**
 * A saved recording can be regenerated with every catalog model except the
 * live ones (Settings/RecordingRow.swift, `regenerateModelSections`).
 */
export const REGENERATE_MODEL_COUNT = MODEL_CATALOG.filter((m) => !m.live).length;

/** "$0.36 per hour", for prose. */
export function pricePerHour(model: Pick<ModelFact, "pricePerHourUSD">): string {
  return `$${model.pricePerHourUSD.toFixed(2)} per hour`;
}

// One array feeds both the visible FAQ on /meeting-recording and the FAQPage
// JSON-LD below, so the two can never disagree. Keep it at 11 entries or fewer.
export const meetingFaqEntries: FaqEntry[] = [
  {
    question: "Is VoiceToText free? What costs money?",
    answer: `VoiceToText is free, with source available on GitHub and no paid tier, account, trial, or per-minute fee. Recording, transcribing with a local model, History, and search cost nothing however much you record. Three optional extras can cost money, billed by the provider to your own API key: cloud transcription models, speaker labels with ${DIARIZE_MODEL.name} (${pricePerHour(DIARIZE_MODEL)} of audio at list price), and AI summaries or action items, which OpenAI bills per use. The same app also does hotkey dictation into any text field.`,
  },
  {
    question: "Does it work with Zoom, Google Meet, and Microsoft Teams?",
    answer:
      "Yes, and with FaceTime, Webex, Discord, or any other app that plays the call through your Mac. VoiceToText records your microphone and the Mac's system audio together and mixes them into one recording, so the other participants are recorded along with you. It is a separate Mac app, not a plugin: nothing is installed in Zoom, Google Meet needs no browser extension, and there is no Teams app to approve. System audio comes through Apple's ScreenCaptureKit, and no bot joins the call.",
  },
  {
    question: "Does it matter whether I'm the host or a participant?",
    answer:
      "No. VoiceToText records what your Mac plays and what your microphone hears, so it works the same whether you host the meeting, co-host it, or join someone else's call, in the app or in a browser. It doesn't use the meeting app's own Record button, so that app's recording settings don't decide whether it can record. Being able to record is not the same as having everyone's agreement, so ask first.",
  },
  {
    question: "Will other people see a bot or get notified that I'm recording?",
    answer:
      "No bot or extra participant appears, and VoiceToText doesn't notify anyone: it records on your Mac without touching the call. If you share your screen, others may see the small Recording HUD; you can turn it off in Settings → Conversations. Because nobody is told automatically, telling people is up to you. Recording laws differ between countries and states, and some require everyone's consent, so say that you're recording and follow the rules that apply to you and your workplace.",
  },
  {
    question: "Is meeting recording private, and which permissions does it need?",
    answer:
      "With a local model, the recording is transcribed on your Mac and the audio stays there. Conversations use the “Same as dictation” model by default, which is on-device Parakeet unless you changed it. Audio goes to a provider only when a cloud model transcribes it, directly under your own API key. AI summaries and action items send the transcript text, not the audio, to OpenAI, and only when you ask for one. macOS asks for two permissions: Microphone, for your voice, and Screen & System Audio Recording, which is how an app gets system audio. VoiceToText records only the audio, never the screen. Accessibility is used only by dictation.",
  },
  {
    question: "Can VoiceToText identify and label different speakers?",
    answer: `Yes, with the optional cloud model ${DIARIZE_MODEL.name} and your OpenAI API key. Choose it as the Transcription model in Conversations, or regenerate an existing recording with it. The transcript comes back as turns labeled Speaker 1, Speaker 2, and so on. Use Name speakers to replace the labels with real names; giving two labels the same name merges their turns. The audio is sent to OpenAI at a list price of ${pricePerHour(DIARIZE_MODEL)}, billed to your key. Local Parakeet and Whisper models do not separate speakers.`,
  },
  {
    question: "Can it summarize meetings and pull out action items?",
    answer: `Yes, once you add an OpenAI API key. From the sparkles menu on any recording you can generate a Summary, an Action Items checklist, or up to three results from your own prompt, such as meeting minutes or a follow-up email. Each action item is a task, with an owner and a due date only when someone actually said them; tick items off and copy the list as a Markdown checklist. These run on OpenAI's ${AI_TEXT_MODEL} with your key and send the transcript text, including speaker names, to OpenAI. Transcription itself can still happen on your Mac.`,
  },
  {
    question: "How do I start recording, and which microphone does it use?",
    answer: `Click Start Recording in Conversations, choose Start Conversation Recording from the menu bar, or press your Conversation shortcut in any app (set one in Settings → Shortcut; there is no default key). Press Stop & Transcribe, or the shortcut again, to finish; Cancel deletes the recording without a transcript. There is no pause, and VoiceToText doesn't detect meetings or start recording by itself. ${MICROPHONE_SETTING}`,
  },
  {
    question: "Can I record voice notes or a solo recording without a call?",
    answer:
      "Yes. Start a conversation recording with no call running and talk: it records your microphone, along with anything else the Mac is playing, and saves the audio and transcript in History. For a quick note you want typed into an app, use dictation instead: press ⌥Space, speak, review, and the text is pasted at your cursor. Search transcripts in History finds words across every recording, summary, and action item. Conversations stay until you delete them; History keeps your newest 200 dictations.",
  },
  {
    question: "What happens with long meetings, or if the app crashes mid-recording?",
    answer:
      "Recordings longer than 12 minutes are transcribed in parts of about 10 minutes, each cut at the quietest nearby moment to avoid splitting words, with progress shown. The audio streams to disk while you record. If the app crashes, is force-quit, or the Mac loses power, the audio is repaired and filed into History on the next launch without a transcript; choose Regenerate to transcribe it. If macOS stops the capture or the disk fills up mid-call, VoiceToText says why, then saves and transcribes everything recorded up to that point. If transcription fails, the audio is kept so you can try again.",
  },
  {
    question: "Can I transcribe an existing file, or re-transcribe a recording with another model?",
    answer: `Yes to both. In Conversations, click Upload File… or drag one audio or video file onto the pane. Files macOS can read work, such as MP3, M4A, WAV, AIFF, FLAC, MP4, and MOV; MKV, WebM, and AVI do not. History keeps the extracted audio, and your original file is left untouched. Every recording also keeps its audio, so you can regenerate the transcript with any of the ${REGENERATE_MODEL_COUNT} models that transcribe recordings, for example switching from on-device Parakeet to a cloud model for a difficult call. The earlier transcript is kept beside the new one, so you can compare them and remove the one you don't want.`,
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
    "Free meeting recorder for Mac with source available on GitHub and no account. Records microphone and system audio together from Zoom, Google Meet, Microsoft Teams, or any call app, with no bot in the call, transcribes on-device by default, and offers optional cloud speaker labels, AI summaries, and action-item checklists using your own OpenAI key.",
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
