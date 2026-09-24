import { codingVoiceToTextConfig } from "@/components/seo/use-case-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(codingVoiceToTextConfig, {
  title: "Voice to text for coding — a practical Mac workflow",
  description:
    "Dictate detailed prompts, bug reports, comments, and review notes; keep exact syntax and sensitive values on the keyboard.",
});

export default function VoiceToTextForCodingPage() {
  return <SeoLandingPage config={codingVoiceToTextConfig} />;
}
