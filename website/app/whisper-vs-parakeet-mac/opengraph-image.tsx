import { renderOgImage } from "@/lib/og-image";

export const alt = "Whisper vs Parakeet on Mac · choosing a local speech model in VoiceToText";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Local model guide",
    title: "Whisper vs. Parakeet",
    titleMuted: "on your Mac.",
    subtitle:
      "Six local models, one choice: how they differ in accuracy, languages, and download size inside VoiceToText.",
    chips: ["6 local models", "Free to run", "Audio stays on your Mac"],
  });
}
