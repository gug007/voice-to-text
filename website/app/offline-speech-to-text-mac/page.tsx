import type { Metadata } from "next";

import { SeoLandingPage } from "@/components/seo/seo-landing";
import { offlineSpeechToTextConfig } from "@/components/seo/use-case-page-data";
import { AUTHOR_URL, SITE_URL } from "@/lib/constants";

const PATH = "/offline-speech-to-text-mac";
const TITLE = "Offline Speech to Text for Mac — Private, Free";
const DESCRIPTION =
  "Run speech to text locally on an Apple Silicon Mac. Learn what stays offline, how to set it up, which model to choose, and where cloud features begin.";

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
    title: "Offline speech to text for Mac — what stays local",
    description:
      "A practical guide to local models, network boundaries, setup, privacy, and offline transcription on Apple Silicon.",
    images: ["/opengraph-image"],
  },
};

export default function OfflineSpeechToTextMacPage() {
  return <SeoLandingPage config={offlineSpeechToTextConfig} />;
}

