"use client";

import type { CSSProperties } from "react";
import { useEffect, useState, useSyncExternalStore } from "react";

const SENTENCE = "Quick update: I finished the proposal and shared it with the team.";
const HUD_BAR_COUNT = 34;
const TICK_MS = 300;
const TYPE_CHARS_PER_TICK = 7;
const RECORD_TICKS = 12; // 3.6 s of "recording"
const REVIEW_TICKS = 9; // 2.7 s in the review panel
const HOLD_TICKS = 8; // 2.4 s with the pasted sentence in place

type Phase = "rec" | "review" | "paste";
type StageState = { phase: Phase; ticks: number; typed: number };

const INITIAL: StageState = { phase: "rec", ticks: 0, typed: 0 };
const SETTLED: StageState = { phase: "paste", ticks: HOLD_TICKS, typed: SENTENCE.length };

function advance(s: StageState): StageState {
  switch (s.phase) {
    case "rec":
      return s.ticks >= RECORD_TICKS
        ? { phase: "review", ticks: 0, typed: 0 }
        : { ...s, ticks: s.ticks + 1 };
    case "review":
      return s.ticks >= REVIEW_TICKS
        ? { phase: "paste", ticks: 0, typed: 0 }
        : { ...s, ticks: s.ticks + 1 };
    case "paste":
      if (s.typed < SENTENCE.length) {
        return { ...s, typed: Math.min(SENTENCE.length, s.typed + TYPE_CHARS_PER_TICK) };
      }
      return s.ticks >= HOLD_TICKS ? INITIAL : { ...s, ticks: s.ticks + 1 };
  }
}

type HudBarVars = CSSProperties & Record<"--h" | "--d" | "--delay", string>;

// Deterministic so the server and client render identical bars.
function hudBarStyle(i: number): HudBarVars {
  const h = 18 + 78 * Math.abs(Math.sin(i * 0.55 + 1.1)) * (0.55 + 0.45 * Math.abs(Math.cos(i * 0.21)));
  const d = 0.5 + ((i * 29) % 7) / 10;
  const delay = -((i * 41) % 13) / 10;
  return { "--h": `${h.toFixed(0)}%`, "--d": `${d.toFixed(2)}s`, "--delay": `${delay.toFixed(2)}s` };
}

const STEPS: { n: number; label: string; activeIn: readonly Phase[] }[] = [
  { n: 1, label: "Press ⌥ Space", activeIn: ["rec"] },
  { n: 2, label: "Speak", activeIn: ["rec", "review"] },
  { n: 3, label: "It pastes anywhere", activeIn: ["paste"] },
];

/**
 * Hero product stage: a text field, the recording HUD, and the review panel
 * cycling through record → review → paste. Decorative; the real explanation
 * lives in the "What happens when you speak" section.
 */
const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)";

function subscribeReducedMotion(notify: () => void): () => void {
  const media = window.matchMedia(REDUCED_MOTION_QUERY);
  media.addEventListener("change", notify);
  return () => media.removeEventListener("change", notify);
}

export function HeroStage() {
  const reducedMotion = useSyncExternalStore(
    subscribeReducedMotion,
    () => window.matchMedia(REDUCED_MOTION_QUERY).matches,
    () => false,
  );
  const [cycle, setCycle] = useState<StageState>(INITIAL);

  useEffect(() => {
    if (reducedMotion) return;
    const id = window.setInterval(() => setCycle(advance), TICK_MS);
    return () => window.clearInterval(id);
  }, [reducedMotion]);

  // With reduced motion the stage rests on the finished state instead of cycling.
  const { phase, ticks, typed } = reducedMotion ? SETTLED : cycle;
  const recording = phase === "rec";
  const reviewing = phase === "review";
  const landed = phase === "paste" && typed >= SENTENCE.length;
  const fieldText = phase === "paste" ? SENTENCE.slice(0, typed) : "";
  const showCaret = recording || (phase === "paste" && !landed);
  const seconds = recording ? Math.floor((ticks * TICK_MS) / 1000) : 0;

  const hint = recording
    ? "Recording…"
    : reviewing
      ? "Return to paste"
      : landed
        ? "Pasted at cursor ✓"
        : "Pasting…";
  const hintClass = recording ? "stage__hint stage__hint--live" : landed ? "stage__hint stage__hint--ready" : "stage__hint";

  return (
    <div className="stage" data-phase={phase} aria-hidden="true">
      <div className="stage__steps">
        {STEPS.map(({ n, label, activeIn }) => (
          <span key={n} className={`stage__step${activeIn.includes(phase) ? " is-active" : ""}`}>
            <span className="stage__step-num">{n}</span>
            {label}
          </span>
        ))}
      </div>

      <div className={`stage__field${recording ? " is-recording" : ""}`}>
        <div className="stage__text">
          <span className={`stage__placeholder${recording || fieldText ? " is-hidden" : ""}`}>
            Speak into any text field on your Mac…
          </span>
          <span className="stage__typed">{fieldText}</span>
          <span className={`stage__caret${showCaret ? " is-visible" : ""}`} />
        </div>
        <div className="stage__bar">
          <span className="stage__mic">
            <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round">
              <rect x="7" y="2" width="6" height="11" rx="3" />
              <path d="M4 10a6 6 0 0012 0M10 16v3" />
            </svg>
          </span>
          <span className={hintClass}>{hint}</span>
          <span className="stage__keys">
            <kbd>⌥</kbd>
            <kbd>Space</kbd>
          </span>
        </div>
      </div>

      <div className="stage__stack">
        <div className={`stage__hud${recording ? " is-visible" : ""}`}>
          <div className="stage__hud-bars">
            {Array.from({ length: HUD_BAR_COUNT }, (_, i) => (
              <span key={i} style={hudBarStyle(i)} />
            ))}
          </div>
          <div className="stage__hud-foot">
            <span className="stage__hud-timer">{`0:0${seconds}`}</span>
            <span>⌥ Space to stop · Esc cancels</span>
          </div>
        </div>

        <figure className={`stage__review${reviewing ? " is-visible" : ""}`}>
          <figcaption>
            <span className="stage__review-dot" />
            Review before paste
          </figcaption>
          <p>{SENTENCE}</p>
          <div className="stage__review-keys">
            <span><kbd className="keycap">Return</kbd> Paste</span>
            <span><kbd className="keycap">Esc</kbd> Cancel</span>
          </div>
        </figure>
      </div>
    </div>
  );
}
