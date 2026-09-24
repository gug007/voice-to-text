import { renderOgImage } from "@/lib/og-image";

export const alt = "Best dictation apps for Mac — seven apps compared with an open methodology";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "2026 Mac comparison · open methodology",
    title: "The best dictation app",
    titleMuted: "depends on the job.",
    chips: ["Apple", "Wispr", "Superwhisper", "MacWhisper", "Aqua", "VoiceInk", "VoiceToText"],
  });
}
