import { whisperVsParakeetConfig } from "@/components/seo/model-and-apple-page-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(whisperVsParakeetConfig, {
  title: "Parakeet vs Whisper on Mac: which local model?",
  description:
    "Parakeet TDT v3 vs Whisper Large v3 and four more local models: two public WER benchmarks, 25 vs 99 languages, download sizes, and a fair test.",
});

export default function WhisperVsParakeetMacPage() {
  return <SeoLandingPage config={whisperVsParakeetConfig} />;
}
