import { GUIDE_PATH, GUIDE_URL, SITE_URL } from "./constants";
import { page } from "./pages";
import { PERSON_ID, SOFTWARE_ID, WEBSITE_ID, type FaqEntry } from "./seo-ids";

/* ---------- Mac voice-to-text guide ---------- */

export const GUIDE_PUBLISHED = page(GUIDE_PATH).published;
export const GUIDE_UPDATED = page(GUIDE_PATH).modified;

export const GUIDE_H1 = "How to use voice to text on Mac — in any app.";

export const guideArticleJsonLd = {
  "@context": "https://schema.org",
  "@type": "Article",
  "@id": `${GUIDE_URL}#article`,
  headline: GUIDE_H1,
  description:
    "A practical guide to voice typing on a Mac: turning on the built-in Dictation and its shortcut, then setting up VoiceToText with permissions, the recording card and review panel keys, a local model for your language, optional AI actions, and fixes for common problems.",
  url: GUIDE_URL,
  mainEntityOfPage: { "@id": `${GUIDE_URL}#webpage` },
  image: {
    "@type": "ImageObject",
    url: `${GUIDE_URL}/opengraph-image`,
    width: 1200,
    height: 630,
  },
  datePublished: GUIDE_PUBLISHED,
  dateModified: GUIDE_UPDATED,
  author: { "@id": PERSON_ID },
  publisher: { "@id": PERSON_ID },
  about: { "@id": SOFTWARE_ID },
  articleSection: "Mac dictation",
  inLanguage: "en",
} as const;

export const guidePageJsonLd = {
  "@context": "https://schema.org",
  "@type": "WebPage",
  "@id": `${GUIDE_URL}#webpage`,
  url: GUIDE_URL,
  name: "How to use voice to text on Mac",
  description:
    "Turn on Mac Dictation and learn its shortcut, or set up VoiceToText: grant the right permissions, choose an offline model that covers your language, review before pasting, troubleshoot common problems, and dictate into any app.",
  datePublished: GUIDE_PUBLISHED,
  dateModified: GUIDE_UPDATED,
  isPartOf: { "@id": WEBSITE_ID },
  mainEntity: { "@id": `${GUIDE_URL}#article` },
  about: { "@id": SOFTWARE_ID },
  breadcrumb: { "@id": `${GUIDE_URL}#breadcrumb` },
  inLanguage: "en",
} as const;

export const guideBreadcrumbJsonLd = {
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "@id": `${GUIDE_URL}#breadcrumb`,
  itemListElement: [
    { "@type": "ListItem", position: 1, name: "Home", item: `${SITE_URL}/` },
    { "@type": "ListItem", position: 2, name: "Mac voice-to-text guide", item: GUIDE_URL },
  ],
} as const;

// One array feeds both the visible FAQ on the guide and the FAQPage JSON-LD
// below, so the two can never disagree. The built-in answers follow Apple's Mac
// User Guide ("Dictate messages and documents on Mac") and its Mac keyboard
// shortcuts page; re-check them there when macOS changes.
export const guideFaqEntries: FaqEntry[] = [
  {
    question: "How do I turn on voice to text on Mac?",
    answer:
      "Choose Apple menu → System Settings, click Keyboard in the sidebar, go to Dictation and turn it on, then click Enable. To dictate, click where the text should go and press the Microphone key, use your Dictation keyboard shortcut, or choose Edit → Start Dictation. VoiceToText is a separate free app for when you want to review the text before it is pasted.",
  },
  {
    question: "What is the keyboard shortcut for voice to text on Mac?",
    answer:
      "Press the Microphone key in the top row if your keyboard has one. Apple's keyboard shortcut list also gives Fn-D (Globe-D) to start or stop dictation. In System Settings → Keyboard → Dictation, the Shortcut menu shows the shortcut your Mac uses and lets you pick another, such as pressing Fn (🌐) twice, or choose Customize to record your own. Press Esc to stop. VoiceToText uses Option-Space by default.",
  },
  {
    question: "Does voice to text on Mac work offline?",
    answer:
      "It depends on your language and settings. To check, open System Settings → Keyboard and read the text below Dictation: it says whether your voice input is processed on your Mac rather than sent to Siri servers. Apple lists the languages with on-device Dictation on its macOS Feature Availability page, and they may need a one-time download of speech models. VoiceToText's local models work with the network off after a one-time download.",
  },
  {
    question: "How do I add punctuation when dictating on Mac?",
    answer:
      "In supported languages, Mac Dictation inserts commas, periods and question marks for you. You can also say the mark, such as “comma” or “exclamation mark”, or say “new line” or “new paragraph”. VoiceToText has no spoken punctuation: its models punctuate from how you speak, and spoken cues are typed as words.",
  },
  {
    question: "Can I use voice to text in any app on Mac?",
    answer:
      "Yes. Apple Dictation works anywhere you can type. VoiceToText pastes its text into any app where Command-V pastes text, such as Mail, Notes, Slack, a browser or a terminal.",
  },
];

export const guideFaqPageJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "@id": `${GUIDE_URL}#faq-page`,
  url: `${GUIDE_URL}#faq`,
  isPartOf: { "@id": `${GUIDE_URL}#webpage` },
  mainEntity: guideFaqEntries.map(({ question, answer }) => ({
    "@type": "Question",
    name: question,
    acceptedAnswer: { "@type": "Answer", text: answer },
  })),
} as const;
