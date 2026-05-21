import { ImageResponse } from "next/og";

export const alt = "VoiceToText — free voice to text for Mac, push-to-talk dictation that types into any app";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const COLORS = {
  bg: "#0A0A0B",
  textPrimary: "#F4F4F5",
  textSecondary: "#A1A1AA",
  textMuted: "#8A8A94",
  border: "#2A2A31",
  surface: "#17171A",
};

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          background: COLORS.bg,
          color: COLORS.textPrimary,
          display: "flex",
          flexDirection: "column",
          padding: "80px",
          position: "relative",
        }}
      >
        {/* subtle dot grid */}
        <div
          style={{
            position: "absolute",
            inset: 0,
            backgroundImage:
              "radial-gradient(circle at 1px 1px, rgba(255,255,255,0.04) 1px, transparent 0)",
            backgroundSize: "32px 32px",
            opacity: 0.6,
          }}
        />

        <div style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 28, color: COLORS.textMuted, letterSpacing: "0.06em", textTransform: "uppercase" }}>
          <span
            style={{
              width: 12,
              height: 12,
              borderRadius: 6,
              background: COLORS.textPrimary,
              display: "flex",
            }}
          />
          VoiceToText &middot; voicetotext.cc
        </div>

        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center" }}>
          <div
            style={{
              fontSize: 110,
              fontWeight: 700,
              letterSpacing: "-0.035em",
              lineHeight: 1.02,
              color: COLORS.textPrimary,
            }}
          >
            Voice to Text
          </div>
          <div
            style={{
              fontSize: 110,
              fontWeight: 700,
              letterSpacing: "-0.035em",
              lineHeight: 1.02,
              color: COLORS.textSecondary,
            }}
          >
            for Mac. Free.
          </div>

          <div
            style={{
              marginTop: 40,
              fontSize: 36,
              lineHeight: 1.4,
              color: COLORS.textSecondary,
              maxWidth: 920,
            }}
          >
            Hold Option+Space, speak, release &mdash; your words type at the
            cursor in Slack, Notes, Mail, ChatGPT, or any Mac app.
          </div>
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 24, fontSize: 26, color: COLORS.textMuted }}>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 12,
              padding: "10px 20px",
              border: `1px solid ${COLORS.border}`,
              borderRadius: 12,
              background: COLORS.surface,
              color: COLORS.textPrimary,
            }}
          >
            <span style={{ fontWeight: 600 }}>Free</span>
          </div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 12,
              padding: "10px 20px",
              border: `1px solid ${COLORS.border}`,
              borderRadius: 12,
              background: COLORS.surface,
              color: COLORS.textPrimary,
            }}
          >
            <span style={{ fontWeight: 600 }}>Open source</span>
          </div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 12,
              padding: "10px 20px",
              border: `1px solid ${COLORS.border}`,
              borderRadius: 12,
              background: COLORS.surface,
              color: COLORS.textPrimary,
            }}
          >
            <span style={{ fontWeight: 600 }}>Offline on Apple Silicon</span>
          </div>
        </div>
      </div>
    ),
    { ...size },
  );
}
