import type { CSSProperties } from "react";

const COLORS = ["#FF5F57", "#FEBC2E", "#28C840"] as const;

/** The three macOS window-chrome dots. Purely decorative. */
export function TrafficLights() {
  return (
    <>
      {COLORS.map((color) => (
        <span
          key={color}
          className="macos-window__dot"
          style={{ "--c": color } as CSSProperties & Record<"--c", string>}
        />
      ))}
    </>
  );
}
