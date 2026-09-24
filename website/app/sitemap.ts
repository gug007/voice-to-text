import type { MetadataRoute } from "next";

import { PAGES, pageUrl, type PagePath } from "@/lib/pages";

// Generated from the PAGES registry, so a page's lastModified is the same date
// its OpenGraph tags, JSON-LD and visible "Updated" line show. Bump `modified`
// in lib/pages.ts only on real content changes; a per-build timestamp would
// fake freshness to crawlers.
export default function sitemap(): MetadataRoute.Sitemap {
  return (Object.keys(PAGES) as PagePath[]).map((path) => {
    const { modified, changeFrequency, priority } = PAGES[path];
    return {
      url: pageUrl(path),
      lastModified: modified,
      changeFrequency,
      priority,
    };
  });
}
