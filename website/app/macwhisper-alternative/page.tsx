import { macwhisperAlternativeConfig } from "@/components/seo/new-alternatives-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(macwhisperAlternativeConfig, {
  title: "A free MacWhisper alternative for dictation and meetings",
  description:
    "Dictation into any app, bot-free meeting capture, and local models, free. MacWhisper's file and export strengths included.",
});

export default function MacWhisperAlternativePage() {
  return <SeoLandingPage config={macwhisperAlternativeConfig} />;
}
