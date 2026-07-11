import { ImageResponse } from "next/og";

export const alt = "How to use voice to text on Mac — a free offline setup guide from VoiceToText";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const COLORS = {
  bg: "#0A0A0B",
  text: "#F4F4F5",
  secondary: "#A1A1AA",
  muted: "#8A8A94",
  border: "#2A2A31",
  surface: "#17171A",
};

export default function GuideOpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          padding: "72px 80px",
          display: "flex",
          flexDirection: "column",
          position: "relative",
          color: COLORS.text,
          background: COLORS.bg,
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            backgroundImage:
              "radial-gradient(circle at 1px 1px, rgba(255,255,255,0.045) 1px, transparent 0)",
            backgroundSize: "32px 32px",
          }}
        />

        <div style={{ display: "flex", alignItems: "center", gap: 14, fontSize: 26, color: COLORS.muted }}>
          <span style={{ width: 11, height: 11, display: "flex", borderRadius: 6, background: COLORS.text }} />
          VoiceToText &middot; Practical Mac guide
        </div>

        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center" }}>
          <div style={{ fontSize: 88, fontWeight: 700, lineHeight: 1.04, letterSpacing: "-0.04em" }}>
            How to use voice
          </div>
          <div style={{ fontSize: 88, fontWeight: 700, lineHeight: 1.04, letterSpacing: "-0.04em", color: COLORS.secondary }}>
            to text on Mac.
          </div>
          <div style={{ marginTop: 32, fontSize: 31, lineHeight: 1.35, color: COLORS.secondary }}>
            Install → press Option+Space → speak → review and paste.
          </div>
        </div>

        <div style={{ display: "flex", gap: 16 }}>
          {["About 5 minutes", "Works in any app", "Offline by default"].map((label) => (
            <div
              key={label}
              style={{
                display: "flex",
                padding: "10px 18px",
                border: `1px solid ${COLORS.border}`,
                borderRadius: 12,
                background: COLORS.surface,
                color: COLORS.text,
                fontSize: 24,
              }}
            >
              {label}
            </div>
          ))}
        </div>
      </div>
    ),
    { ...size },
  );
}
