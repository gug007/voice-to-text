import { renderOgImage } from "@/lib/og-image";

export const alt = "VoiceToText comparisons · Mac dictation and transcription apps, side by side";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Comparisons",
    title: "VoiceToText",
    titleMuted: "and the alternatives.",
    subtitle:
      "Wispr Flow, Superwhisper, Apple Dictation, Granola and MacWhisper: where each wins, with sources and dates.",
    chips: ["Competitor wins included", "Sources linked", "Dated"],
  });
}
