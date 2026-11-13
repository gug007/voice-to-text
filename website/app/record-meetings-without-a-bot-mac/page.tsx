import { noBotMeetingConfig } from "@/components/seo/meeting-pages-data";
import { landingMetadata, SeoLandingPage } from "@/components/seo/seo-landing";

export const metadata = landingMetadata(noBotMeetingConfig, {
  title: "Record Zoom, Meet and Teams calls on Mac without a bot",
  description:
    "Mic + system audio, captured on your Mac with nothing joining the meeting. Transcribed on-device by default, free, no account.",
});

export default function RecordMeetingsWithoutABotMacPage() {
  return <SeoLandingPage config={noBotMeetingConfig} />;
}
