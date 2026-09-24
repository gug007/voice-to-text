import type { Metadata } from "next";
import Link from "next/link";

import { JsonLd } from "@/components/json-ld";
import { ScrollEffects } from "@/components/scroll-effects";
import { Contributors } from "@/components/sections/contributors";
import { Conversations } from "@/components/sections/conversations";
import { Demo } from "@/components/sections/demo";
import { Download } from "@/components/sections/download";
import { Everywhere } from "@/components/sections/everywhere";
import { Faq } from "@/components/sections/faq";
import { Features } from "@/components/sections/features";
import { Footer } from "@/components/sections/footer";
import { Hero } from "@/components/sections/hero";
import { Models } from "@/components/sections/models";
import { Nav } from "@/components/sections/nav";
import { Story } from "@/components/sections/story";
import { StickyCta } from "@/components/sticky-cta";
import { Icon } from "@/components/ui/icon";
import type { PagePath } from "@/lib/pages";
import { getLatestRelease } from "@/lib/release";
import { SITE_URL } from "@/lib/constants";
import {
  HOME_DESCRIPTION,
  HOME_TITLE,
  HOME_TWITTER_DESCRIPTION,
  INDEXABLE_ROBOTS,
  faqPageJsonLd,
  homePageJsonLd,
  personJsonLd,
  softwareApplicationJsonLd,
  videoObjectJsonLd,
  websiteJsonLd,
} from "@/lib/seo";

// Title and canonical live here, not in the root layout, so they aren't
// inherited by routes that must not claim them (e.g. the 404 page).
// Metadata merges shallowly, so openGraph repeats the layout's site-wide fields.
export const metadata: Metadata = {
  title: HOME_TITLE,
  description: HOME_DESCRIPTION,
  alternates: { canonical: "/" },
  robots: INDEXABLE_ROBOTS,
  openGraph: {
    type: "website",
    siteName: "VoiceToText",
    locale: "en_US",
    url: SITE_URL,
    title: HOME_TITLE,
    description: HOME_DESCRIPTION,
  },
  twitter: {
    card: "summary_large_image",
    title: HOME_TITLE,
    description: HOME_TWITTER_DESCRIPTION,
  },
};

type ReadNextLink = { href: PagePath; title: string; body: string };

const TOPIC_GUIDES: readonly ReadNextLink[] = [
  {
    href: "/offline-speech-to-text-mac",
    title: "Offline speech to text on Mac",
    body: "How the local Parakeet and Whisper models keep transcription on your Apple Silicon Mac after a one-time download, and where cloud features begin.",
  },
  {
    href: "/voice-to-text-for-coding",
    title: "Voice to text for coding",
    body: "Dictate prompts, implementation notes, and terminal commands into Cursor, Claude Code, ChatGPT, and other coding tools.",
  },
  {
    href: "/meeting-recording",
    title: "Record and transcribe meetings",
    body: "Capture your microphone and the call’s audio together with no bot in the meeting, transcribe on your Mac by default, and add summaries with your own OpenAI key.",
  },
];

// In-content links into the comparison cluster. Each line only restates what
// the linked page itself covers.
const COMPARISONS: readonly ReadNextLink[] = [
  {
    href: "/wispr-flow-alternative",
    title: "VoiceToText vs Wispr Flow",
    body: "Local or cloud transcription, accounts, privacy controls, and where each one fits.",
  },
  {
    href: "/superwhisper-alternative",
    title: "VoiceToText vs Superwhisper",
    body: "Local models, formatting, file workflows, source access, and who each app suits.",
  },
  {
    href: "/apple-dictation-alternative",
    title: "VoiceToText vs Apple Dictation",
    body: "When the built-in tool is enough, and what a review step and model choice add.",
  },
  {
    href: "/granola-alternative",
    title: "VoiceToText vs Granola",
    body: "Meeting capture compared: what each app records, where transcription runs, and the tradeoffs.",
  },
  {
    href: "/macwhisper-alternative",
    title: "VoiceToText vs MacWhisper",
    body: "File transcription, dictation, and local models on a Mac, side by side.",
  },
  {
    href: "/whisper-vs-parakeet-mac",
    title: "Whisper vs Parakeet on Mac",
    body: "Which local model to pick, by language, accuracy, and download size.",
  },
  {
    href: "/compare/best-dictation-apps-for-mac",
    title: "Best dictation apps for Mac (2026)",
    body: "Seven apps compared on dictation, file transcription, meetings, privacy, languages, and price.",
  },
  {
    href: "/compare",
    title: "All comparisons",
    body: "Every VoiceToText comparison in one place.",
  },
];

function ReadNextList({ links, compact = false }: { links: readonly ReadNextLink[]; compact?: boolean }) {
  return (
    <ul className={compact ? "guide-list guide-list--compact" : "guide-list"} role="list">
      {links.map(({ href, title, body }) => (
        <li key={href}>
          <Link className="guide-list__item" href={href} prefetch={false}>
            <span>
              <span className="guide-list__t">{title}</span>
              <span className="guide-list__d">{body}</span>
            </span>
            <Icon name="arrow-right" className="guide-list__chevron" />
          </Link>
        </li>
      ))}
    </ul>
  );
}

export default async function Home() {
  const release = await getLatestRelease();
  // The product entity carries the shipping version, so it tracks each release
  // without a hand edit.
  const softwareJsonLd = {
    ...softwareApplicationJsonLd,
    softwareVersion: release.version,
    releaseNotes: release.url,
  };

  return (
    <>
      <JsonLd data={softwareJsonLd} />
      <JsonLd data={websiteJsonLd} />
      <JsonLd data={homePageJsonLd} />
      <JsonLd data={videoObjectJsonLd} />
      <JsonLd data={faqPageJsonLd} />
      <JsonLd data={personJsonLd} />
      <Nav />
      <main id="main" tabIndex={-1}>
        <Hero release={release} />
        <Story />
        <Demo />
        <Conversations />
        <Features />
        <Models />
        <Everywhere />
        <Contributors />
        <section className="section" id="guides" aria-labelledby="guides-title">
          <div className="wrap">
            <div className="sec-head">
              <p className="kicker">Aside &middot; read next</p>
              <h2 id="guides-title">Guides and comparisons.</h2>
              <p className="lede">
                Setup notes for private dictation, coding by voice, and meeting transcripts, plus side-by-side
                comparisons with the apps you might be weighing it against.
              </p>
            </div>
            <div className="guides">
              <div>
                <h3 className="guides__h">Guides</h3>
                <ReadNextList links={TOPIC_GUIDES} />
              </div>
              <div>
                <h3 className="guides__h">Comparisons</h3>
                <ReadNextList links={COMPARISONS} compact />
              </div>
            </div>
          </div>
        </section>
        <Faq />
        <Download release={release} />
      </main>
      <Footer />
      <StickyCta />
      <ScrollEffects />
    </>
  );
}
