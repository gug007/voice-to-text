import { whisperVsParakeetConfig } from "@/components/seo/model-and-apple-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(whisperVsParakeetConfig, {
  title: whisperVsParakeetConfig.title,
  description: whisperVsParakeetConfig.description,
});

export default function WhisperVsParakeetMacPage() {
  return <SeoLandingPage config={whisperVsParakeetConfig} />;
}
