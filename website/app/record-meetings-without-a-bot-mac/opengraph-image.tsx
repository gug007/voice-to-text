import { renderOgImage } from "@/lib/og-image";

export const alt =
  "Record Zoom, Google Meet and Teams calls on a Mac without a bot: VoiceToText captures mic and system audio and transcribes on-device by default";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Meeting recording",
    title: "Record the call.",
    titleMuted: "No bot joins it.",
    subtitle:
      "Your mic and the Mac’s system audio from Zoom, Google Meet, Teams or FaceTime, transcribed on your Mac by default.",
    chips: ["Zoom · Meet · Teams", "Nothing joins the call", "Free"],
  });
}
