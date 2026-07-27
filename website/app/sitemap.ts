import type { MetadataRoute } from "next";

import { GUIDE_URL, SITE_URL } from "@/lib/constants";
import { MEETING_URL } from "@/lib/seo";

export default function sitemap(): MetadataRoute.Sitemap {
  // Bump when page content meaningfully changes; a per-build timestamp would
  // fake freshness to crawlers.
  const homeLastModified = "2026-07-27";
  const contentPageLastModified = "2026-07-27";
  const newContentLastModified = "2026-07-27";
  return [
    {
      url: `${SITE_URL}/`,
      lastModified: homeLastModified,
      changeFrequency: "monthly",
      priority: 1.0,
    },
    {
      url: GUIDE_URL,
      lastModified: contentPageLastModified,
      changeFrequency: "monthly",
      priority: 0.9,
    },
    {
      url: MEETING_URL,
      lastModified: contentPageLastModified,
      changeFrequency: "monthly",
      priority: 0.8,
    },
    {
      url: `${SITE_URL}/offline-speech-to-text-mac`,
      lastModified: newContentLastModified,
      changeFrequency: "monthly",
      priority: 0.85,
    },
    {
      url: `${SITE_URL}/voice-to-text-for-coding`,
      lastModified: newContentLastModified,
      changeFrequency: "monthly",
      priority: 0.85,
    },
    {
      url: `${SITE_URL}/apple-dictation-alternative`,
      lastModified: newContentLastModified,
      changeFrequency: "monthly",
      priority: 0.8,
    },
    {
      url: `${SITE_URL}/whisper-vs-parakeet-mac`,
      lastModified: newContentLastModified,
      changeFrequency: "monthly",
      priority: 0.8,
    },
    {
      url: `${SITE_URL}/superwhisper-alternative`,
      lastModified: newContentLastModified,
      changeFrequency: "monthly",
      priority: 0.75,
    },
    {
      url: `${SITE_URL}/wispr-flow-alternative`,
      lastModified: newContentLastModified,
      changeFrequency: "monthly",
      priority: 0.75,
    },
  ];
}
