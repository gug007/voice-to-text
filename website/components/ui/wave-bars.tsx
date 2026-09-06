import type { CSSProperties } from "react";

const WAVE_BAR_COUNT = 72;

type BarVars = CSSProperties & Record<"--i" | "--peak" | "--d" | "--delay", string | number>;

function barStyle(i: number): BarVars {
  const peak = 0.28 + 0.6 * Math.abs(Math.sin(i * 0.41 + 0.8)) * (0.7 + 0.3 * Math.abs(Math.cos(i * 0.13)));
  const duration = 1.3 + ((i * 37) % 11) / 10;
  const delay = -((i * 53) % 17) / 10;
  return {
    "--i": i,
    "--peak": peak.toFixed(3),
    "--d": `${duration.toFixed(2)}s`,
    "--delay": `${delay.toFixed(2)}s`,
  };
}

/** Decorative level meter behind hero sections, in the spirit of the app's recording HUD. */
export function WaveBars() {
  return (
    <div className="dictation-wave" aria-hidden="true">
      <div className="bars">
        {Array.from({ length: WAVE_BAR_COUNT }, (_, i) => (
          <i key={i} style={barStyle(i)} />
        ))}
      </div>
    </div>
  );
}
