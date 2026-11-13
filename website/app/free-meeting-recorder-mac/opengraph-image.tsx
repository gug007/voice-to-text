import { renderOgImage } from "@/lib/og-image";

export const alt =
  "A free meeting recorder for Mac: VoiceToText records and transcribes meetings on-device with no account, trial or minute cap";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Free meeting recorder",
    title: "Record meetings free.",
    titleMuted: "No account, no caps.",
    subtitle:
      "Recording, on-device transcription and search cost nothing. Optional cloud extras are billed to your own API key.",
    chips: ["No account", "No minute cap", "On-device by default"],
  });
}
