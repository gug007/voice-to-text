import { dragonForMacAlternativeConfig } from "@/components/seo/dragon-alternative-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(dragonForMacAlternativeConfig, {
  title: "Mac dictation vs Dragon: what replaced Dragon for Mac",
  description:
    "Dragon for Mac ended in 2018. Where Apple Dictation, Voice Control and VoiceToText each fit, and where VoiceToText falls short. Sources linked.",
});

export default function DragonForMacAlternativePage() {
  return <SeoLandingPage config={dragonForMacAlternativeConfig} />;
}
