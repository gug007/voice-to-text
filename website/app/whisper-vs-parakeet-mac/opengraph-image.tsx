import { renderOgImage } from "@/lib/og-image";

export const alt = "Parakeet vs Whisper on Mac · Parakeet TDT v3 compared with Whisper Large v3 and Turbo in VoiceToText";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Local model guide",
    title: "Parakeet vs. Whisper",
    titleMuted: "on your Mac.",
    subtitle:
      "Six local models, one choice: how they differ in accuracy, languages, and download size inside VoiceToText.",
    chips: ["6 local models", "Free to run", "Audio stays on your Mac"],
  });
}
