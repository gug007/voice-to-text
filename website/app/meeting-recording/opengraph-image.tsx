import { renderOgImage } from "@/lib/og-image";

export const alt =
  "VoiceToText meeting recorder for Mac: mic plus system audio with no bot, on-device transcripts by default, optional summaries and action items with your OpenAI key";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Meeting recording",
    title: "Record meetings",
    titleMuted: "on your Mac. Free.",
    subtitle:
      "Capture your mic and the call’s system audio from Zoom, Meet, Teams or FaceTime. Transcribe on-device by default; add your OpenAI key for summaries and action items.",
    chips: ["No meeting bot", "On-device by default", "Summaries & action items"],
  });
}
