import type { Metadata } from "next";
import Link from "next/link";

import { JsonLd } from "@/components/json-ld";
import { ScrollEffects } from "@/components/scroll-effects";
import { Contributors } from "@/components/sections/contributors";
import { Demo } from "@/components/sections/demo";
import { Download } from "@/components/sections/download";
import { Faq } from "@/components/sections/faq";
import { Features } from "@/components/sections/features";
import { Footer } from "@/components/sections/footer";
import { Hero } from "@/components/sections/hero";
import { HowItWorks } from "@/components/sections/how-it-works";
import { Nav } from "@/components/sections/nav";
import { Proof } from "@/components/sections/proof";
import { StickyCta } from "@/components/sticky-cta";
import { Icon } from "@/components/ui/icon";
import { UseCaseExplorer } from "@/components/use-case-explorer";
import {
  faqPageJsonLd,
  homePageJsonLd,
  personJsonLd,
  softwareApplicationJsonLd,
  videoObjectJsonLd,
  websiteJsonLd,
} from "@/lib/seo";

// Canonical lives here, not in the root layout, so it isn't inherited by
// routes that must not claim it (e.g. the 404 page).
export const metadata: Metadata = {
  alternates: { canonical: "/" },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
      "max-video-preview": -1,
    },
  },
};

const TOPIC_GUIDES = [
  {
    href: "/offline-speech-to-text-mac",
    title: "Offline speech to text on Mac",
    body: "See how local Whisper and Parakeet models keep transcription on your Apple Silicon Mac after the one-time download.",
  },
  {
    href: "/voice-to-text-for-coding",
    title: "Voice to text for coding",
    body: "Dictate prompts, implementation notes, and terminal commands into Cursor, Claude Code, ChatGPT, and other coding tools.",
  },
  {
    href: "/meeting-recording",
    title: "Record and transcribe meetings",
    body: "Capture your microphone and system audio together, then transcribe calls locally by default, with no bot in the meeting.",
  },
] as const;

export default function Home() {
  return (
    <>
      <JsonLd data={softwareApplicationJsonLd} />
      <JsonLd data={websiteJsonLd} />
      <JsonLd data={homePageJsonLd} />
      <JsonLd data={videoObjectJsonLd} />
      <JsonLd data={faqPageJsonLd} />
      <JsonLd data={personJsonLd} />
      <Nav />
      <main id="main" tabIndex={-1}>
        <Hero />
        <Proof />
        <Demo />
        <HowItWorks />
        <UseCaseExplorer />
        <section className="section guide-section" id="guides" aria-labelledby="guides-title">
          <div className="container">
            <div className="section__head">
              <h2 id="guides-title" className="section__title">
                Guides for the workflow you want to improve.
              </h2>
              <p className="section__deck">
                Practical setup notes for private dictation, faster coding, and meeting transcription on a Mac.
              </p>
            </div>
            <ul className="guide-list" role="list">
              {TOPIC_GUIDES.map(({ href, title, body }) => (
                <li key={href}>
                  <Link className="guide-list__item" href={href}>
                    <span>
                      <h3>{title}</h3>
                      <p>{body}</p>
                    </span>
                    <Icon name="arrow-right" className="guide-list__chevron" />
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        </section>
        <Features />
        <Contributors />
        <Faq />
        <Download />
      </main>
      <Footer />
      <StickyCta />
      <ScrollEffects />
    </>
  );
}
