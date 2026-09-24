import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { ImageResponse } from "next/og";

// One generator for every route's opengraph-image, drawn in the site's Clear
// Coat light theme: a white plate on the canvas, the app icon as the brand
// mark, and the dictation-wave gradient as the only colour. Route files keep
// their own literal `alt` / `size` / `contentType` exports and call this.

export const OG_SIZE = { width: 1200, height: 630 } as const;

// Light-theme tokens from app/globals.css (satori can't read CSS variables).
const COLORS = {
  canvas: "#FFFFFF",
  plate: "#F6F7F9",
  border: "rgba(25, 21, 42, 0.12)",
  text: "#19152A",
  secondary: "#3D434E",
  muted: "#515762",
  chip: "#FFFFFF",
  brandStart: "#6194FF",
  brandEnd: "#854FF7",
} as const;

// Fixed bar heights (px) for the wave motif, echoing the home hero's wave bars.
const WAVE = [18, 30, 46, 64, 52, 80, 96, 72, 58, 88, 104, 76, 50, 66, 42, 28, 38, 22];

export type OgImageContent = {
  /** Short label after the brand name, e.g. "Meeting recording". */
  eyebrow: string;
  /** First headline line, in full-strength ink. */
  title: string;
  /** Optional second headline line, in the secondary ink. */
  titleMuted?: string;
  subtitle?: string;
  /** Up to about four short labels along the bottom. */
  chips?: readonly string[];
};

let iconDataUrl: Promise<string | null> | undefined;

function loadIcon(): Promise<string | null> {
  iconDataUrl ??= readFile(join(process.cwd(), "public/app-icon.png"))
    .then((buf) => `data:image/png;base64,${buf.toString("base64")}`)
    .catch(() => null);
  return iconDataUrl;
}

function titleSize(lines: string[]): number {
  const longest = Math.max(...lines.map((line) => line.length));
  if (longest <= 17) return 80;
  if (longest <= 21) return 72;
  if (longest <= 25) return 64;
  return 56;
}

export async function renderOgImage({
  eyebrow,
  title,
  titleMuted,
  subtitle,
  chips = [],
}: OgImageContent): Promise<ImageResponse> {
  const icon = await loadIcon();
  const fontSize = titleSize(titleMuted ? [title, titleMuted] : [title]);
  const headline = {
    display: "flex",
    fontSize,
    fontWeight: 700,
    letterSpacing: "-0.035em",
    lineHeight: 1.04,
  } as const;

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          padding: 36,
          background: COLORS.canvas,
        }}
      >
        <div
          style={{
            flex: 1,
            display: "flex",
            flexDirection: "column",
            padding: "52px 64px",
            background: COLORS.plate,
            border: `1px solid ${COLORS.border}`,
            borderRadius: 36,
            boxShadow: "0 1px 2px rgba(25, 21, 42, 0.06), 0 12px 32px rgba(25, 21, 42, 0.06)",
            color: COLORS.text,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 26 }}>
            {icon ? (
              // eslint-disable-next-line @next/next/no-img-element -- satori renders plain <img>
              <img src={icon} width={48} height={48} alt="" style={{ borderRadius: 11 }} />
            ) : null}
            <span style={{ display: "flex", fontWeight: 700, color: COLORS.text }}>VoiceToText</span>
            <span style={{ display: "flex", color: COLORS.muted }}>&middot;</span>
            <span style={{ display: "flex", color: COLORS.muted }}>{eyebrow}</span>
          </div>

          <div
            style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", padding: "24px 0" }}
          >
            <div style={{ ...headline, color: COLORS.text }}>{title}</div>
            {titleMuted ? <div style={{ ...headline, color: COLORS.muted }}>{titleMuted}</div> : null}
            {subtitle ? (
              <div
                style={{
                  display: "flex",
                  marginTop: 24,
                  maxWidth: 880,
                  fontSize: 28,
                  lineHeight: 1.4,
                  color: COLORS.secondary,
                }}
              >
                {subtitle}
              </div>
            ) : null}
          </div>

          <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between", gap: 32 }}>
            <div style={{ flex: 1, display: "flex", flexWrap: "wrap", gap: 12 }}>
              {chips.map((label) => (
                <span
                  key={label}
                  style={{
                    display: "flex",
                    padding: "10px 20px",
                    border: `1px solid ${COLORS.border}`,
                    borderRadius: 999,
                    background: COLORS.chip,
                    color: COLORS.text,
                    fontSize: 22,
                    fontWeight: 600,
                  }}
                >
                  {label}
                </span>
              ))}
            </div>
            <div style={{ display: "flex", flexShrink: 0, alignItems: "center", gap: 6, height: 104 }}>
              {WAVE.map((height, i) => (
                <span
                  key={i}
                  style={{
                    display: "flex",
                    width: 8,
                    height,
                    borderRadius: 4,
                    backgroundImage: `linear-gradient(180deg, ${COLORS.brandStart}, ${COLORS.brandEnd})`,
                  }}
                />
              ))}
            </div>
          </div>
        </div>
      </div>
    ),
    { ...OG_SIZE },
  );
}
