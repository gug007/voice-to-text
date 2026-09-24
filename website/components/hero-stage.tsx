"use client";

import type { CSSProperties } from "react";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";

const TRANSCRIPT = "Ship the release notes on Thursday, then ping design for the final screenshots.";

const TICK_MS = 300;

type Phase = "idle" | "rec" | "transcribing" | "pasted";

// Ticks spent in each phase: ~9 s per loop.
const SCHEDULE: ReadonlyArray<readonly [Phase, number]> = [
  ["idle", 5],
  ["rec", 12],
  ["transcribing", 3],
  ["pasted", 10],
];

type Cycle = { step: number; ticks: number };

const INITIAL: Cycle = { step: 1, ticks: 0 };
// Under reduced motion the stage rests on the result: the text pasted in place.
const SETTLED: Cycle = { step: SCHEDULE.findIndex(([phase]) => phase === "pasted"), ticks: 0 };

function advance({ step, ticks }: Cycle): Cycle {
  if (ticks + 1 < SCHEDULE[step][1]) return { step, ticks: ticks + 1 };
  return { step: (step + 1) % SCHEDULE.length, ticks: 0 };
}

// The app's LevelBars: 56 capsules, oldest to newest, with the `0.20 + 0.65t`
// opacity ramp. Deterministic, so server and client render identical bars.
const BAR_COUNT = 56;

type BarVars = CSSProperties & Record<"--o" | "--h" | "--d" | "--delay", string>;

function barStyle(i: number): BarVars {
  const t = i / (BAR_COUNT - 1);
  const level = 0.16 + 0.66 * Math.abs(Math.sin(i * 0.43 + 0.4)) * (0.6 + 0.4 * Math.abs(Math.cos(i * 0.17)));
  return {
    "--o": (0.2 + 0.65 * t).toFixed(3),
    "--h": `${(8 + 92 * level).toFixed(1)}%`,
    "--d": `${(0.58 + ((i * 29) % 9) / 10).toFixed(2)}s`,
    "--delay": `${(-((i * 43) % 15) / 10).toFixed(2)}s`,
  };
}

const STEPS: ReadonlyArray<{ label: string; phases: readonly Phase[] }> = [
  { label: "Press ⌥Space", phases: ["idle"] },
  { label: "Speak", phases: ["rec", "transcribing"] },
  { label: "Pasted at your cursor", phases: ["pasted"] },
];

const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)";

function subscribeReducedMotion(notify: () => void): () => void {
  const media = window.matchMedia(REDUCED_MOTION_QUERY);
  media.addEventListener("change", notify);
  return () => media.removeEventListener("change", notify);
}

function Key({ children }: { children: string }) {
  return <em>{children}</em>;
}

/**
 * Hero product stage: a Mail compose window and the app's floating HUD,
 * cycling record → transcribe → paste.
 * Decorative and aria-hidden; the story section below says the same in text.
 * The box has a fixed height in every phase, so nothing around it moves.
 */
export function HeroStage() {
  const reducedMotion = useSyncExternalStore(
    subscribeReducedMotion,
    () => window.matchMedia(REDUCED_MOTION_QUERY).matches,
    () => false,
  );
  const [cycle, setCycle] = useState<Cycle>(INITIAL);
  const [onScreen, setOnScreen] = useState(true);
  const rootRef = useRef<HTMLDivElement>(null);

  // Stop ticking while the stage is scrolled away; CSS loops pause through
  // `data-pause-offscreen`, this pauses the state machine the same way.
  useEffect(() => {
    const el = rootRef.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const io = new IntersectionObserver(([entry]) => setOnScreen(entry.isIntersecting), { rootMargin: "120px 0px" });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  useEffect(() => {
    if (reducedMotion || !onScreen) return;
    const id = window.setInterval(() => {
      if (!document.hidden) setCycle(advance);
    }, TICK_MS);
    return () => window.clearInterval(id);
  }, [reducedMotion, onScreen]);

  const { step, ticks } = reducedMotion ? SETTLED : cycle;
  const phase = SCHEDULE[step][0];
  const seconds = phase === "rec" ? Math.floor((ticks * TICK_MS) / 1000) : 3;
  const activeStep = STEPS.findIndex(({ phases }) => phases.includes(phase));
  const hudHidden = phase === "idle" || phase === "pasted";

  return (
    <div className="hstage" data-phase={phase} data-pause-offscreen aria-hidden="true" ref={rootRef}>
      <div className="hstage__frame">
        <div className="hstage__win">
          <div className="hstage__bar">
            <span className="dot dot--r" />
            <span className="dot dot--y" />
            <span className="dot dot--g" />
            <span className="hstage__title">New Message</span>
            <span className="win__pad" />
          </div>
          <div className="hstage__row">
            <span>To:</span>
            <b>Design team</b>
          </div>
          <div className="hstage__row">
            <span>Subject:</span>
            <b>Thursday release</b>
          </div>
          <div className="hstage__body">
            {phase === "pasted" ? <span className="hstage__pasted">{TRANSCRIPT}</span> : null}
            <span className="hstage__caret" />
          </div>
        </div>

        <div className="hstage__hud" data-hidden={hudHidden || undefined}>
          <div className="hstage__pane">
            <span className="hstage__meter">
              {Array.from({ length: BAR_COUNT }, (_, i) => (
                <i key={i} style={barStyle(i)} />
              ))}
            </span>
            <span className="hstage__controls">
              {phase === "transcribing" ? (
                <>
                  <span className="hstage__shimmer">Transcribing</span>
                  <span className="hstage__clock">0.4s</span>
                </>
              ) : (
                <span className="hstage__clock">{`0:0${seconds}`}</span>
              )}
              <span className="hstage__spacer" />
              <span className="hstage__btn">
                Cancel <Key>esc</Key>
              </span>
              {phase === "transcribing" ? null : (
                <span className="hstage__btn hstage__btn--primary">
                  Finish <Key>⌥Space</Key>
                </span>
              )}
            </span>
          </div>
        </div>
      </div>

      <ol className="hstage__steps">
        {STEPS.map(({ label }, i) => (
          <li key={label} className={i === activeStep ? "is-active" : i < activeStep ? "is-done" : undefined}>
            <b>{i + 1}</b>
            {label}
          </li>
        ))}
      </ol>
    </div>
  );
}
