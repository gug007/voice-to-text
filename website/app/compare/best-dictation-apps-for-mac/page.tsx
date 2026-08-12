import type { Metadata } from "next";

import { BestDictationAppsPage } from "@/components/compare/best-dictation-apps";
import { AUTHOR_URL, SITE_URL } from "@/lib/constants";

const PATH = "/compare/best-dictation-apps-for-mac";
const TITLE = "Best Dictation Apps for Mac (2026): An Honest Comparison";
const DESCRIPTION =
  "Compare seven Mac dictation apps across dictation, file transcription, meetings, correction workflow, privacy path, languages, and price—with a reproducible test protocol.";

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
    publishedTime: "2026-08-12",
    modifiedTime: "2026-08-12",
    authors: [AUTHOR_URL],
    images: [{ url: `${PATH}/opengraph-image`, width: 1200, height: 630, alt: TITLE }],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: "Seven apps. Seven decision points. Competitor wins included. Unrun metrics left unranked.",
    images: [`${PATH}/opengraph-image`],
  },
};

export default function Page() {
  return <BestDictationAppsPage />;
}
