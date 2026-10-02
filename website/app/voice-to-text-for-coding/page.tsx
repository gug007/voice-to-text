import { codingVoiceToTextConfig } from "@/components/seo/use-case-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(codingVoiceToTextConfig, {
  title: "Voice coding on Mac: a practical voice-to-text workflow",
  description:
    "Dictate prompts, bug reports and review notes into Cursor, VS Code and terminals with a free, source-available app, local by default.",
});

export default function VoiceToTextForCodingPage() {
  return <SeoLandingPage config={codingVoiceToTextConfig} />;
}
