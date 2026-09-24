import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [{ protocol: "https", hostname: "avatars.githubusercontent.com" }],
  },
  async headers() {
    return [
      {
        // The comparison page links its benchmark artifacts (methodology,
        // manifest, CSV template, fixtures) so anyone can re-run the test. They
        // stay reachable, but shouldn't compete with the page in search results.
        // Headers are applied before the filesystem, so this covers /public.
        source: "/compare/best-dictation-apps-for-mac/:file(.+\\.(?:md|json|csv|txt))",
        headers: [{ key: "X-Robots-Tag", value: "noindex" }],
      },
    ];
  },
};

export default nextConfig;
