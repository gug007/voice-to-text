import { renderOgImage } from "@/lib/og-image";

export const alt = "Apple Dictation vs VoiceToText · the built-in tool compared with a free Mac app";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Apple Dictation alternative",
    title: "Apple Dictation",
    titleMuted: "vs. VoiceToText.",
    subtitle:
      "Both free. Compare review before paste, model choice, privacy, and meeting capture — and where the built-in tool wins.",
    chips: ["Both free", "Review before paste", "Local models"],
  });
}
