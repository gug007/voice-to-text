import type { MetadataRoute } from "next";

import { GUIDE_URL, SITE_URL } from "@/lib/constants";
import { MEETING_URL } from "@/lib/seo";

export default function sitemap(): MetadataRoute.Sitemap {
  // Bump when page content meaningfully changes; a per-build timestamp would
  // fake freshness to crawlers.
  const lastModified = "2026-07-11";
  return [
    {
      url: `${SITE_URL}/`,
      lastModified,
      changeFrequency: "monthly",
      priority: 1.0,
    },
    {
      url: GUIDE_URL,
      lastModified,
      changeFrequency: "monthly",
      priority: 0.9,
    },
    {
      url: MEETING_URL,
      lastModified,
      changeFrequency: "monthly",
      priority: 0.8,
    },
  ];
}
