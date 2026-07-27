import type { Metadata } from "next";

import { SeoLandingPage } from "@/components/seo/seo-landing";
import { wisprFlowAlternativeConfig } from "@/components/seo/vendor-comparison-page-data";
import { AUTHOR_URL, SITE_URL } from "@/lib/constants";

const PATH = "/wispr-flow-alternative";
const TITLE = "Wispr Flow Alternative for Mac — Local & Free";
const DESCRIPTION =
  "Compare VoiceToText and Wispr Flow for Mac dictation: local versus cloud transcription, privacy controls, platforms, accounts, formatting, and tradeoffs.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: PATH },
  robots: { index: true, follow: true },
  openGraph: {
    type: "article",
    url: `${SITE_URL}${PATH}`,
    siteName: "VoiceToText",
    title: TITLE,
    description: DESCRIPTION,
    locale: "en_US",
    publishedTime: "2026-07-27",
    modifiedTime: "2026-07-27",
    authors: [AUTHOR_URL],
    images: [{ url: "/opengraph-image", width: 1200, height: 630, alt: TITLE }],
  },
  twitter: {
    card: "summary_large_image",
    title: "A local-first Wispr Flow alternative for Mac",
    description:
      "Compare on-device and cloud transcription, privacy controls, platforms, formatting, and governance.",
    images: ["/opengraph-image"],
  },
};

export default function WisprFlowAlternativePage() {
  return <SeoLandingPage config={wisprFlowAlternativeConfig} />;
}
