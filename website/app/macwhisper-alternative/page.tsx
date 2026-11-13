import { macwhisperAlternativeConfig } from "@/components/seo/new-alternatives-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(macwhisperAlternativeConfig, {
  title: "MacWhisper alternative for Mac: free, local, no account",
  description:
    "Free dictation and bot-free call recording with local models, vs MacWhisper's exports and subtitles. Who should switch, plus other MacWhisper alternatives.",
});

export default function MacWhisperAlternativePage() {
  return <SeoLandingPage config={macwhisperAlternativeConfig} />;
}
