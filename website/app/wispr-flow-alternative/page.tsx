import { wisprFlowAlternativeConfig } from "@/components/seo/vendor-comparison-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(wisprFlowAlternativeConfig, {
  title: "Wispr Flow alternative for Mac (2026): free and offline",
  description:
    "On-device vs cloud transcription, meeting notes and AI summaries, privacy controls, platforms and price, checked against Wispr’s own docs.",
});

export default function WisprFlowAlternativePage() {
  return <SeoLandingPage config={wisprFlowAlternativeConfig} />;
}
