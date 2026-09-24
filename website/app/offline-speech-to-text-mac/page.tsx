import { offlineSpeechToTextConfig } from "@/components/seo/use-case-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(offlineSpeechToTextConfig, {
  title: "Offline speech to text for Mac — what stays local",
  description:
    "A practical guide to local models, network boundaries, setup, privacy, and offline transcription on Apple Silicon.",
});

export default function OfflineSpeechToTextMacPage() {
  return <SeoLandingPage config={offlineSpeechToTextConfig} />;
}
