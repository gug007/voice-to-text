import type { MetadataRoute } from "next";

import { SITE_URL } from "@/lib/constants";

// Nothing is disallowed on purpose: the benchmark artifacts under
// /compare/best-dictation-apps-for-mac/ carry an X-Robots-Tag: noindex header
// (next.config.ts), and crawlers can only see that header if they may fetch them.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/" },
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  };
}
