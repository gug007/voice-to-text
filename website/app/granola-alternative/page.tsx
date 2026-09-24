import { granolaAlternativeConfig } from "@/components/seo/new-alternatives-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(granolaAlternativeConfig, {
  title: "A free, local-first Granola alternative for Mac",
  description:
    "Bot-free meeting capture, on-device transcripts, and optional AI summaries with your own key. Granola's wins included.",
});

export default function GranolaAlternativePage() {
  return <SeoLandingPage config={granolaAlternativeConfig} />;
}
