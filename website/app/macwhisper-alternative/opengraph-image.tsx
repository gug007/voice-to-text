import { renderOgImage } from "@/lib/og-image";

export const alt = "VoiceToText vs MacWhisper · dictation, meetings and file transcription on Mac";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "MacWhisper alternative",
    title: "VoiceToText",
    titleMuted: "vs. MacWhisper.",
    subtitle:
      "Dictation and meetings first, or files and exports first: compare models, workflows, and price.",
    chips: ["Free, no Pro tier", "Local models", "Dictation + meetings"],
  });
}
