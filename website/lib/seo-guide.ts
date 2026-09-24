import { GUIDE_PATH, GUIDE_URL, SITE_URL } from "./constants";
import { page } from "./pages";
import { PERSON_ID, SOFTWARE_ID, WEBSITE_ID } from "./seo-ids";

/* ---------- Mac voice-to-text guide ---------- */

export const GUIDE_PUBLISHED = page(GUIDE_PATH).published;
export const GUIDE_UPDATED = page(GUIDE_PATH).modified;

export const GUIDE_H1 = "How to use voice to text on Mac — in any app.";

export const guideArticleJsonLd = {
  "@context": "https://schema.org",
  "@type": "Article",
  "@id": `${GUIDE_URL}#article`,
  headline: GUIDE_H1,
  description:
    "A practical guide to setting up voice typing on a Mac: permissions, the shortcut, the recording card and review panel keys, choosing a local model for your language, optional AI actions, and fixes for common problems.",
  url: GUIDE_URL,
  mainEntityOfPage: { "@id": `${GUIDE_URL}#webpage` },
  image: {
    "@type": "ImageObject",
    url: `${GUIDE_URL}/opengraph-image`,
    width: 1200,
    height: 630,
  },
  datePublished: GUIDE_PUBLISHED,
  dateModified: GUIDE_UPDATED,
  author: { "@id": PERSON_ID },
  publisher: { "@id": PERSON_ID },
  about: { "@id": SOFTWARE_ID },
  articleSection: "Mac dictation",
  inLanguage: "en",
} as const;

export const guidePageJsonLd = {
  "@context": "https://schema.org",
  "@type": "WebPage",
  "@id": `${GUIDE_URL}#webpage`,
  url: GUIDE_URL,
  name: "How to use voice to text on Mac",
  description:
    "Set up voice to text on a Mac, grant the right permissions, choose an offline model that covers your language, review before pasting, troubleshoot common problems, and dictate into any app.",
  datePublished: GUIDE_PUBLISHED,
  dateModified: GUIDE_UPDATED,
  isPartOf: { "@id": WEBSITE_ID },
  mainEntity: { "@id": `${GUIDE_URL}#article` },
  about: { "@id": SOFTWARE_ID },
  breadcrumb: { "@id": `${GUIDE_URL}#breadcrumb` },
  inLanguage: "en",
} as const;

export const guideBreadcrumbJsonLd = {
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "@id": `${GUIDE_URL}#breadcrumb`,
  itemListElement: [
    { "@type": "ListItem", position: 1, name: "Home", item: `${SITE_URL}/` },
    { "@type": "ListItem", position: 2, name: "Mac voice-to-text guide", item: GUIDE_URL },
  ],
} as const;
