import { appleDictationAlternativeConfig } from "@/components/seo/model-and-apple-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(appleDictationAlternativeConfig, {
  title: "Apple Dictation vs. VoiceToText for Mac",
  description:
    "A balanced comparison of the built-in option and a free alternative with source on GitHub, reviewed paste, and local model choice.",
});

export default function AppleDictationAlternativePage() {
  return <SeoLandingPage config={appleDictationAlternativeConfig} />;
}
