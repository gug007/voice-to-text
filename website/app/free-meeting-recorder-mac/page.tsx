import { freeMeetingRecorderConfig } from "@/components/seo/meeting-pages-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(freeMeetingRecorderConfig, {
  title: "A free meeting recorder for Mac: no account, no minute cap",
  description:
    "Recording, on-device transcription and search are free. Cloud models, speaker labels and summaries are optional, billed to your own key.",
});

export default function FreeMeetingRecorderMacPage() {
  return <SeoLandingPage config={freeMeetingRecorderConfig} />;
}
