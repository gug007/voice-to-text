import { renderOgImage } from "@/lib/og-image";

export const alt = "VoiceToText vs Granola · bot-free meeting transcripts on Mac";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Granola alternative",
    title: "VoiceToText",
    titleMuted: "vs. Granola.",
    subtitle:
      "Both skip the meeting bot. Compare where the audio is transcribed, what happens after the call, and the price.",
    chips: ["On-device by default", "No meeting bot", "Free"],
  });
}
