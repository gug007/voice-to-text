import { renderOgImage } from "@/lib/og-image";

export const alt = "How to use voice to text on Mac — a free setup guide from VoiceToText, local by default";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function GuideOpengraphImage() {
  return renderOgImage({
    eyebrow: "Practical Mac guide",
    title: "How to use voice",
    titleMuted: "to text on Mac.",
    subtitle:
      "Install → press Option+Space → speak → review and paste.",
    chips: ["About 8 minutes", "Works in any app", "Local by default"],
  });
}
