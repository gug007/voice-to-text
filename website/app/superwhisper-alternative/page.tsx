import { superwhisperAlternativeConfig } from "@/components/seo/vendor-comparison-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(superwhisperAlternativeConfig, {
  title: "A free, local-first Superwhisper alternative for Mac",
  description:
    "Compare local models, platforms, formatting, meetings, source access, and the tradeoffs that matter.",
});

export default function SuperwhisperAlternativePage() {
  return <SeoLandingPage config={superwhisperAlternativeConfig} />;
}
