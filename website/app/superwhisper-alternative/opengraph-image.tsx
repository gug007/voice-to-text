import { renderOgImage } from "@/lib/og-image";

export const alt = "VoiceToText vs Superwhisper · two Mac dictation apps with local models compared";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Superwhisper alternative",
    title: "VoiceToText",
    titleMuted: "vs. Superwhisper.",
    subtitle:
      "Two Mac dictation apps with local models. Compare price, platforms, formatting, and meeting capture.",
    chips: ["Free", "Source on GitHub", "Local models"],
  });
}
