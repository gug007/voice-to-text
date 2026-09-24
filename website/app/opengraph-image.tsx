import { renderOgImage } from "@/lib/og-image";

export const alt = "VoiceToText — free voice to text for Mac: dictate into any app and transcribe meetings";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "voicetotext.cc",
    title: "Voice to Text",
    titleMuted: "for Mac. Free.",
    subtitle:
      "Press Option+Space and your words land at the cursor in any app. Record calls for a transcript, with optional AI summaries.",
    chips: ["Free", "Source on GitHub", "Offline by default", "No account"],
  });
}
