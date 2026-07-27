import type { Metadata } from "next";

import { appleDictationAlternativeConfig } from "@/components/seo/model-and-apple-page-data";
import { SeoLandingPage } from "@/components/seo/seo-landing";
import { AUTHOR_URL, SITE_URL } from "@/lib/constants";

const PATH = "/apple-dictation-alternative";
const TITLE = "Apple Dictation Alternative for Mac — Free & Offline";
const DESCRIPTION =
  "Compare Apple Dictation with VoiceToText for Mac: installation, privacy, review, model choice, meeting capture, and the situations where the built-in tool wins.";

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
    title: "Apple Dictation vs. VoiceToText for Mac",
    description:
      "A balanced comparison of the built-in option and a free open-source alternative with reviewed paste and local model choice.",
    images: ["/opengraph-image"],
  },
};

export default function AppleDictationAlternativePage() {
  return <SeoLandingPage config={appleDictationAlternativeConfig} />;
}

