import { renderOgImage } from "@/lib/og-image";

export const alt = "Mac dictation vs Dragon · what replaced Dragon for Mac";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Dragon for Mac alternative",
    title: "Mac dictation",
    titleMuted: "vs. Dragon.",
    subtitle:
      "Dragon for Mac was discontinued in 2018. Compare Apple Dictation, Voice Control and VoiceToText.",
    chips: ["Voice Control for commands", "Review before paste", "Free"],
  });
}
