import { whisperVsParakeetConfig } from "@/components/seo/model-and-apple-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(whisperVsParakeetConfig, {
  title: "Whisper vs. Parakeet for local Mac transcription",
  description:
    "Six local models side by side: two public WER benchmarks, languages, download sizes, and a fair test on your own audio.",
});

export default function WhisperVsParakeetMacPage() {
  return <SeoLandingPage config={whisperVsParakeetConfig} />;
}
