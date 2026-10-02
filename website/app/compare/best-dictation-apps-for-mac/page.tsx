import type { Metadata } from "next";

import { BestDictationAppsPage } from "@/components/compare/best-dictation-apps";
import { AUTHOR_URL, SITE_URL } from "@/lib/constants";
import { page } from "@/lib/pages";
import { INDEXABLE_ROBOTS } from "@/lib/seo-ids";

const PATH = "/compare/best-dictation-apps-for-mac";
const TITLE = "7 Best Dictation & Speech-to-Text Apps for Mac (2026)";
const DESCRIPTION =
  "Seven Mac dictation and speech-to-text apps compared on dictation, files, meetings, correction, privacy, languages and price, with a reproducible test.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: PATH },
  robots: INDEXABLE_ROBOTS,
  openGraph: {
    type: "article",
    url: `${SITE_URL}${PATH}`,
    siteName: "VoiceToText",
    title: TITLE,
    description: DESCRIPTION,
    locale: "en_US",
    publishedTime: page(PATH).published,
    modifiedTime: page(PATH).modified,
    authors: [AUTHOR_URL],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description:
      "Seven Mac dictation and speech-to-text apps. Seven decision points. Competitor wins included. Unrun metrics left unranked.",
  },
};

export default function Page() {
  return <BestDictationAppsPage />;
}
