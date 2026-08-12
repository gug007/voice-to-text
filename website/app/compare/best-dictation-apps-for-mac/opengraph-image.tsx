import { ImageResponse } from "next/og";

export const alt = "Best dictation apps for Mac — seven apps compared with an open methodology";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const appNames = ["Apple", "Wispr", "Superwhisper", "MacWhisper", "Aqua", "VoiceInk", "VoiceToText"];

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "72px 78px",
          background: "#08090A",
          color: "#F5F6F7",
          position: "relative",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            backgroundImage: "radial-gradient(circle at 1px 1px, rgba(255,255,255,.045) 1px, transparent 0)",
            backgroundSize: "30px 30px",
          }}
        />
        <div style={{ display: "flex", alignItems: "center", gap: 12, color: "#8B919A", fontSize: 23, letterSpacing: ".08em", textTransform: "uppercase" }}>
          <span style={{ display: "flex", width: 10, height: 10, borderRadius: 5, background: "#22C55E" }} />
          2026 Mac comparison · open methodology
        </div>
        <div style={{ display: "flex", flexDirection: "column", maxWidth: 1000 }}>
          <div style={{ display: "flex", fontSize: 82, fontWeight: 700, letterSpacing: "-.045em", lineHeight: 1.02 }}>
            The best dictation app
          </div>
          <div style={{ display: "flex", fontSize: 82, fontWeight: 700, letterSpacing: "-.045em", lineHeight: 1.02, color: "#A0A4AB" }}>
            depends on the job.
          </div>
        </div>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
          {appNames.map((name) => (
            <span key={name} style={{ display: "flex", padding: "9px 15px", border: "1px solid #292C32", borderRadius: 999, background: "#0F1011", color: "#A0A4AB", fontSize: 19 }}>
              {name}
            </span>
          ))}
        </div>
      </div>
    ),
    size,
  );
}
