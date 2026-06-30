import type { MetadataRoute } from "next";

import { SITE_URL } from "@/lib/constants";
import { MEETING_URL } from "@/lib/seo";

export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date();
  return [
    {
      url: `${SITE_URL}/`,
      lastModified,
      changeFrequency: "monthly",
      priority: 1.0,
    },
    {
      url: MEETING_URL,
      lastModified,
      changeFrequency: "monthly",
      priority: 0.8,
    },
  ];
}
