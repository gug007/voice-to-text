import { renderOgImage } from "@/lib/og-image";

export const alt = "VoiceToText vs Wispr Flow · local vs cloud dictation";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Wispr Flow alternative",
    title: "VoiceToText",
    titleMuted: "vs. Wispr Flow.",
    subtitle:
      "On-device transcription or cloud dictation: compare privacy, accounts, platforms, and cost.",
    chips: ["Local by default", "No account", "Free"],
  });
}
