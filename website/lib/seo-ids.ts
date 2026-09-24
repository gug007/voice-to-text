import type { Metadata } from "next";

import { SITE_URL } from "./constants";

// Shared JSON-LD @id anchors. Every page's graph points at these, so they live
// in a module with no page content: lib/seo-meeting.ts and lib/seo-guide.ts
// import from here, never from lib/seo.ts, which keeps the graph free of cycles.
export const SOFTWARE_ID = `${SITE_URL}/#software`;
export const WEBSITE_ID = `${SITE_URL}/#website`;
export const PERSON_ID = `${SITE_URL}/#creator`;
export const HOME_PAGE_ID = `${SITE_URL}/#webpage`;
export const VIDEO_ID = `${SITE_URL}/#product-demo-video`;

export type FaqEntry = { question: string; answer: string };

// Next merges metadata shallowly, so a page that sets `robots` replaces the
// layout's value outright. Every indexable page sets this one object.
export const INDEXABLE_ROBOTS = {
  index: true,
  follow: true,
  googleBot: {
    index: true,
    follow: true,
    "max-image-preview": "large",
    "max-snippet": -1,
    "max-video-preview": -1,
  },
} as const satisfies Metadata["robots"];
