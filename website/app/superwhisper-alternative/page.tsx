import { superwhisperAlternativeConfig } from "@/components/seo/vendor-comparison-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(superwhisperAlternativeConfig, {
  title: "Superwhisper alternative for Mac: free, local, no account",
  description:
    "Free local dictation, review before paste and meeting recording, vs Superwhisper's platforms and Super Mode. Who should switch, plus other alternatives.",
});

export default function SuperwhisperAlternativePage() {
  return <SeoLandingPage config={superwhisperAlternativeConfig} />;
}
