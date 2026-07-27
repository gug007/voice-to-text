import type { Metadata } from "next";
import Link from "next/link";

import { JsonLd } from "@/components/json-ld";
import { ScrollEffects } from "@/components/scroll-effects";
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
    body: "Capture your microphone and system audio together, then transcribe calls locally by default—without a bot in the meeting.",
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
        <section className="section guide-section reveal" id="guides" aria-labelledby="guides-title">
          <div className="container guide__container">
            <p className="section__eyebrow">Mac speech-to-text guides</p>
            <h2 id="guides-title" className="section__title">
              Pick the voice workflow you want to improve.
            </h2>
            <p className="section__deck">
              Practical guides for private dictation, faster coding, and meeting transcription on Mac.
            </p>
            <div className="guide__choices">
              {TOPIC_GUIDES.map(({ href, title, body }) => (
                <article key={href} className="guide__choice">
                  <h3><Link className="link" href={href}>{title}</Link></h3>
                  <p>{body}</p>
                </article>
              ))}
            </div>
          </div>
        </section>
        <Features />
        <Faq />
        <Download />
      </main>
      <Footer />
      <StickyCta />
      <ScrollEffects />
    </>
  );
}
