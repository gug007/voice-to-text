import type { CSSProperties } from "react";

import { Glyph } from "@/components/ui/glyph";

// The app's LevelBars at the pill's size (HUDMetrics.pill): 20 capsules, oldest
// to newest, with the `0.20 + 0.65t` opacity ramp. Deterministic, so server and
// client render identical bars.
const BAR_COUNT = 20;

type BarVars = CSSProperties & Record<"--o" | "--h" | "--d" | "--delay", string>;

function barStyle(i: number): BarVars {
  const t = i / (BAR_COUNT - 1);
  const level = 0.16 + 0.7 * Math.abs(Math.sin(i * 0.83 + 0.4)) * (0.6 + 0.4 * Math.abs(Math.cos(i * 0.31)));
  return {
    "--o": (0.2 + 0.65 * t).toFixed(3),
    "--h": `${(14 + 86 * level).toFixed(1)}%`,
    "--d": `${(0.58 + ((i * 29) % 9) / 10).toFixed(2)}s`,
    "--delay": `${(-((i * 43) % 15) / 10).toFixed(2)}s`,
  };
}

/**
 * The Small recording HUD, the app's default (UI/HUDCompactRow.swift): one
 * capsule with the recording dot, the level meter, the clock, and Cancel and
 * Finish as circles. The app keeps their names and keys in tooltips, so the
 * pill prints no key hints. `transcribing` is the hand-off after Finish: the
 * dot and meter freeze grey and a spinner holds Finish's slot.
 * Decorative: always rendered inside aria-hidden art, and nothing in it is a control.
 */
export function HudPill({ clock, transcribing = false }: { clock: string; transcribing?: boolean }) {
  return (
    <span className="hud" data-busy={transcribing || undefined}>
      <span className="hud__dot" />
      <span className="hud__bars">
        {Array.from({ length: BAR_COUNT }, (_, i) => (
          <i key={i} style={barStyle(i)} />
        ))}
      </span>
      <span className="hud__t">{clock}</span>
      <span className="hud__controls">
        <span className="hud__icon">
          <Glyph name="xmark" />
        </span>
        {transcribing ? (
          <span className="hud__icon hud__icon--busy">
            <span className="hud__spin" />
          </span>
        ) : (
          <span className="hud__icon hud__icon--primary">
            <Glyph name="checkmark" />
          </span>
        )}
      </span>
    </span>
  );
}
