import { renderOgImage } from "@/lib/og-image";

export const alt = "Voice to text for coding on Mac · dictate prompts, bug reports and review notes";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return renderOgImage({
    eyebrow: "Voice to text for coding",
    title: "Dictate the prompt.",
    titleMuted: "Type the syntax.",
    subtitle:
      "Speak bug reports, review notes, and AI prompts into Cursor, VS Code, or a terminal — and check them before they paste.",
    chips: ["Review before paste", "Works in any editor", "Local by default"],
  });
}
