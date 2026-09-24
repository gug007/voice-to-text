import { SITE_URL } from "./constants";

export type PageRecord = {
  /** ISO date the page first went live. */
  published: string;
  /** ISO date of the last meaningful content change. Bump only on real edits. */
  modified: string;
  /** ISO date third-party (vendor) sources were last re-checked, if the page cites any. */
  sourcesReviewed?: string;
  changeFrequency: "weekly" | "monthly" | "yearly";
  priority: number;
};

// Single source of truth for page dates. The sitemap, OpenGraph times, JSON-LD
// datePublished/dateModified and the visible "Updated" lines all read from here,
// so they can't drift apart.
export const PAGES = {
  "/": { published: "2026-05-21", modified: "2026-09-24", changeFrequency: "monthly", priority: 1.0 },
  "/how-to-use-voice-to-text-on-mac": { published: "2026-07-11", modified: "2026-09-24", changeFrequency: "monthly", priority: 0.9 },
  "/meeting-recording": { published: "2026-06-30", modified: "2026-09-23", changeFrequency: "monthly", priority: 0.9 },
  "/offline-speech-to-text-mac": { published: "2026-07-27", modified: "2026-09-24", changeFrequency: "monthly", priority: 0.85 },
  "/voice-to-text-for-coding": { published: "2026-07-27", modified: "2026-09-23", changeFrequency: "monthly", priority: 0.85 },
  "/whisper-vs-parakeet-mac": { published: "2026-07-27", modified: "2026-09-24", changeFrequency: "monthly", priority: 0.85 },
  "/apple-dictation-alternative": { published: "2026-07-27", modified: "2026-09-24", sourcesReviewed: "2026-07-27", changeFrequency: "monthly", priority: 0.8 },
  "/superwhisper-alternative": { published: "2026-07-27", modified: "2026-09-24", sourcesReviewed: "2026-09-24", changeFrequency: "monthly", priority: 0.8 },
  "/wispr-flow-alternative": { published: "2026-07-27", modified: "2026-09-24", sourcesReviewed: "2026-09-23", changeFrequency: "monthly", priority: 0.8 },
  "/granola-alternative": { published: "2026-09-23", modified: "2026-09-24", sourcesReviewed: "2026-09-23", changeFrequency: "monthly", priority: 0.75 },
  "/macwhisper-alternative": { published: "2026-09-23", modified: "2026-09-24", sourcesReviewed: "2026-09-23", changeFrequency: "monthly", priority: 0.75 },
  "/compare": { published: "2026-09-23", modified: "2026-09-23", changeFrequency: "monthly", priority: 0.8 },
  "/compare/best-dictation-apps-for-mac": { published: "2026-08-12", modified: "2026-09-24", sourcesReviewed: "2026-08-12", changeFrequency: "monthly", priority: 0.9 },
} as const satisfies Record<string, PageRecord>;

export type PagePath = keyof typeof PAGES;

export function page(path: PagePath): PageRecord {
  return PAGES[path];
}

export function pageUrl(path: PagePath): string {
  return path === "/" ? `${SITE_URL}/` : `${SITE_URL}${path}`;
}

/** "2026-09-23" → "September 23, 2026", formatted in UTC so the build machine's zone can't shift the day. */
export function formatDisplayDate(iso: string): string {
  return new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  }).format(new Date(`${iso}T00:00:00Z`));
}
