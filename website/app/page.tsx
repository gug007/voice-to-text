import type { Metadata } from "next";

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
