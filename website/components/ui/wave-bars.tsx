import type { CSSProperties } from "react";

const WAVE_BAR_COUNT = 64;

/** Decorative animated waveform used behind hero sections. */
export function WaveBars() {
  return (
    <div className="dictation-wave" aria-hidden="true">
      <div className="bars">
        {Array.from({ length: WAVE_BAR_COUNT }, (_, i) => (
          <i key={i} style={{ "--i": i } as CSSProperties & Record<"--i", number>} />
        ))}
      </div>
    </div>
  );
}
