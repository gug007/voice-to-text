import type { Metadata } from "next";

import { SeoLandingPage } from "@/components/seo/seo-landing";
import { codingVoiceToTextConfig } from "@/components/seo/use-case-page-data";
import { AUTHOR_URL, SITE_URL } from "@/lib/constants";

const PATH = "/voice-to-text-for-coding";
const TITLE = "Voice to Text for Coding on Mac — Cursor, VS Code & AI";
const DESCRIPTION =
  "Use voice to draft prompts, explain bugs, write comments, and capture implementation notes in Cursor, VS Code, terminals, and AI coding tools on Mac.";

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
    title: "Voice to text for coding — a practical Mac workflow",
    description:
      "Dictate detailed prompts, bug reports, comments, and review notes; keep exact syntax and sensitive values on the keyboard.",
    images: ["/opengraph-image"],
  },
};

export default function VoiceToTextForCodingPage() {
  return <SeoLandingPage config={codingVoiceToTextConfig} />;
}

