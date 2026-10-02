import { offlineSpeechToTextConfig } from "@/components/seo/use-case-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(offlineSpeechToTextConfig, {
  title: "Offline speech to text on Mac: free local transcription",
  description:
    "Local Parakeet and Whisper models transcribe on Apple Silicon with the network off. What stays local, setup, and where cloud features begin.",
});

export default function OfflineSpeechToTextMacPage() {
  return <SeoLandingPage config={offlineSpeechToTextConfig} />;
}
