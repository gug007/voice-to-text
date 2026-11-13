import { granolaAlternativeConfig } from "@/components/seo/new-alternatives-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(granolaAlternativeConfig, {
  title: "Granola alternative for Mac: free, on-device transcripts",
  description:
    "No bot, no account: VoiceToText transcribes calls on your Mac for free. Who should stay with Granola, who should switch, and what stays on the Mac.",
});

export default function GranolaAlternativePage() {
  return <SeoLandingPage config={granolaAlternativeConfig} />;
}
