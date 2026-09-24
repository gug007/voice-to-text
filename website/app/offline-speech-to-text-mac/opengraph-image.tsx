import { renderOgImage } from "@/lib/og-image";

export const alt = "Offline speech to text on Mac · what stays local with VoiceToText";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Offline speech to text",
    title: "Speech to text that",
    titleMuted: "stays on your Mac.",
    subtitle:
      "Local Parakeet and Whisper models run on Apple Silicon after a one-time download. No account, no audio upload.",
    chips: ["Local models", "No account", "Free"],
  });
}
