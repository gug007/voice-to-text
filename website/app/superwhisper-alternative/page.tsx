import type { Metadata } from "next";

import { SeoLandingPage } from "@/components/seo/seo-landing";
import { superwhisperAlternativeConfig } from "@/components/seo/vendor-comparison-page-data";
import { AUTHOR_URL, SITE_URL } from "@/lib/constants";

const PATH = "/superwhisper-alternative";
const TITLE = "Superwhisper Alternative for Mac — Free & Local";
const DESCRIPTION =
  "Compare VoiceToText and Superwhisper for Mac dictation: local models, platforms, formatting, file workflows, source access, requirements, and who each app suits.";

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
    title: "A free, local-first Superwhisper alternative for Mac",
    description:
      "Compare local models, platforms, formatting, meetings, source access, and the tradeoffs that matter.",
    images: ["/opengraph-image"],
  },
};

export default function SuperwhisperAlternativePage() {
  return <SeoLandingPage config={superwhisperAlternativeConfig} />;
}
