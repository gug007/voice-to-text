import { ImageResponse } from "next/og";

export const alt =
  "VoiceToText — record and transcribe meetings on Mac, mic plus system audio, on-device";
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

        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 16,
            fontSize: 28,
            color: COLORS.textMuted,
            letterSpacing: "0.06em",
            textTransform: "uppercase",
          }}
        >
          <span
            style={{
              width: 12,
              height: 12,
              borderRadius: 6,
              background: COLORS.textPrimary,
              display: "flex",
            }}
          />
          VoiceToText &middot; Meeting recording
        </div>

        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center" }}>
          <div
            style={{
              fontSize: 96,
              fontWeight: 700,
              letterSpacing: "-0.035em",
              lineHeight: 1.04,
              color: COLORS.textPrimary,
            }}
          >
            Record meetings
          </div>
          <div
            style={{
              fontSize: 96,
              fontWeight: 700,
              letterSpacing: "-0.035em",
              lineHeight: 1.04,
              color: COLORS.textSecondary,
            }}
          >
            on your Mac. Free.
          </div>

          <div
            style={{
              marginTop: 40,
              fontSize: 34,
              lineHeight: 1.4,
              color: COLORS.textSecondary,
              maxWidth: 960,
            }}
          >
            Capture your mic and the call&rsquo;s system audio together &mdash; Zoom, Meet, Teams, FaceTime
            &mdash; and transcribe it on-device.
          </div>
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 24, fontSize: 26, color: COLORS.textMuted }}>
          {["On-device", "No meeting bot", "Open source"].map((label) => (
            <div
              key={label}
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
              <span style={{ fontWeight: 600 }}>{label}</span>
            </div>
          ))}
        </div>
      </div>
    ),
    { ...size },
  );
}
