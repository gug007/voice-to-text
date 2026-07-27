import type { Metadata } from "next";

import { whisperVsParakeetConfig } from "@/components/seo/model-and-apple-page-data";
import { SeoLandingPage } from "@/components/seo/seo-landing";
import { AUTHOR_URL, SITE_URL } from "@/lib/constants";

const PATH = "/whisper-vs-parakeet-mac";
const TITLE = "Whisper vs. Parakeet on Mac — Which Local Model?";
const DESCRIPTION =
  "Compare Whisper and NVIDIA Parakeet for local speech to text on Mac: languages, model choices, responsiveness, limitations, and how to test your own audio.";

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
    title: "Whisper vs. Parakeet for local Mac transcription",
    description:
      "Model families, tradeoffs, limitations, and a fair test for choosing an on-device speech engine.",
    images: ["/opengraph-image"],
  },
};

export default function WhisperVsParakeetMacPage() {
  return <SeoLandingPage config={whisperVsParakeetConfig} />;
}

