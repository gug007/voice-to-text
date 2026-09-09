"use client";

import type { CSSProperties, ReactNode } from "react";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";

import { GUIDE_PATH } from "@/lib/constants";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";

const TRANSCRIPT = "Ship the release notes, then ping design.";

// The meter mirrors the app's LevelBars: 56 capsules, oldest -> newest, left ->
// right, each springing to its own level. Older samples on the left fade out and
// the write head on the right reads as the current input, so the opacity ramp is
// the app's own `0.20 + 0.65 * t`. Bars are ink, not a tint — the only colour on
// the real HUD is the recording cue.
const HUD_BAR_COUNT = 56;
const HUD_BAR_MIN_HEIGHT = 3; // px floor, so a silent bar is still a baseline

type BarVars = CSSProperties & Record<"--o" | "--h" | "--d" | "--delay", string>;

/** Deterministic, so the server and client render identical bars. */
function hudBarStyle(i: number): BarVars {
  const t = i / (HUD_BAR_COUNT - 1);
  // A plausible speech envelope rather than a uniform block.
  const level =
    0.18 +
    0.62 * Math.abs(Math.sin(i * 0.38 + 0.7)) * (0.62 + 0.38 * Math.abs(Math.cos(i * 0.11)));
  return {
    "--o": (0.2 + 0.65 * t).toFixed(3),
    "--h": `${(HUD_BAR_MIN_HEIGHT + (46 - HUD_BAR_MIN_HEIGHT) * level).toFixed(1)}px`,
    "--d": `${(0.62 + ((i * 31) % 9) / 10).toFixed(2)}s`,
    "--delay": `${(-((i * 47) % 15) / 10).toFixed(2)}s`,
  };
}

function HudBars() {
  return (
    <span className="hud__bars">
      {Array.from({ length: HUD_BAR_COUNT }, (_, i) => (
        <i key={i} style={hudBarStyle(i)} />
      ))}
    </span>
  );
}

function Tick() {
  return (
    <svg
      className="tick"
      viewBox="0 0 12 12"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M1.8 6.4l2.7 2.7L10.2 3" />
    </svg>
  );
}

/* ---------- per-beat art, shown once the sticky stage is dropped ---------- */

function EmptyFieldArt() {
  return (
    <div className="mini">
      <span className="mini__field">
        <span className="mini__ph" />
        <span className="caret" />
      </span>
    </div>
  );
}

function KeysArt() {
  return (
    <div className="mini">
      <span className="mini__keys">
        <kbd>⌥</kbd>
        <kbd>Space</kbd>
      </span>
    </div>
  );
}

function HudArt() {
  return (
    <div className="mini">
      <span className="mini__hud">
        <HudBars />
        <span className="hud__row">
          <span className="hud__t">0:04</span>
          <span className="hud__spacer" />
          <span className="hud__btn">
            Cancel <em>esc</em>
          </span>
        </span>
      </span>
    </div>
  );
}

function ReviewArt() {
  return (
    <div className="mini">
      <span className="mini__card">
        <span className="rv__text">{TRANSCRIPT}</span>
        <span className="rv__foot">
          <span className="rv__key">⏎</span>
          <span className="rv__hint">paste</span>
          <span className="rv__key rv__key--end">esc</span>
        </span>
      </span>
    </div>
  );
}

function PastedArt() {
  return (
    <div className="mini">
      <span className="mini__ok">
        <Tick />
      </span>
      <span className="mini__field">{TRANSCRIPT}</span>
    </div>
  );
}

type Beat = {
  step: number;
  title: ReactNode;
  body: string;
  note: string;
  art: ReactNode;
};

const BEATS: Beat[] = [
  {
    step: 1,
    title: "You’re already in the app.",
    body:
      "There is no window to open and no tab to find. VoiceToText sits in the background while you work in Slack, Mail, Cursor, a browser address bar — anything with a text field.",
    note: "Nothing to launch. No per-app setup, ever.",
    art: <EmptyFieldArt />,
  },
  {
    step: 2,
    title: (
      <>
        Press <HotkeyCombo />.
      </>
    ),
    body:
      "One global hotkey, and it is rebindable — even to Right Control on its own, if that is the key your hands already reach for. That one asks for Input Monitoring permission.",
    note: "Toggle by default. Prefer hold to talk? Push-to-talk is a switch in Settings.",
    art: <KeysArt />,
  },
  {
    step: 3,
    title: "Say what you mean.",
    body:
      "A small HUD with a live waveform appears over whatever you are doing. Speak in full sentences, casual or technical — punctuation is inferred. With a streaming model, the words appear as you say them.",
    note: "Esc cancels at any time, and in local mode the audio never leaves the Mac.",
    art: <HudArt />,
  },
  {
    step: 4,
    title: "Read it before anyone else does.",
    body:
      "The transcript pops up for a quick edit. Fix a name, cut a sentence, or just glance at it and move on — you see the text before your colleagues do.",
    note: "In a hurry? Turn review off and it pastes instantly.",
    art: <ReviewArt />,
  },
  {
    step: 5,
    title: "It types where your cursor was.",
    body:
      "Return pastes the text into the field you were already in — the composer, the terminal, the address bar. macOS calls the ability to do that Accessibility. It is how one app is allowed to type into another; it is not keylogging.",
    note: "Back to work — you never left the app you were in.",
    art: <PastedArt />,
  },
];

const SIDE_ROWS = 7;

const MESSAGES: ReadonlyArray<{ name: string; initials: string; avatar?: string; lines: string[] }> = [
  { name: "Kavi", initials: "K", lines: ["", "w2"] },
  { name: "Rui", initials: "R", avatar: "ava--2", lines: ["w3"] },
  { name: "Tomas", initials: "T", avatar: "ava--3", lines: ["w5", "w4"] },
  { name: "Eibhlin", initials: "Ei", avatar: "ava--4", lines: ["w2"] },
  { name: "Kavi", initials: "K", lines: ["w3", "w4"] },
  { name: "Rui", initials: "R", avatar: "ava--2", lines: ["w5"] },
];

/** Decorative: everything the stage illustrates is written out in the beats. */
function Stage({ step }: { step: number }) {
  return (
    <div className="stage" data-state={step}>
      <div className="win">
        <div className="win__bar">
          <span className="dot dot--r" />
          <span className="dot dot--y" />
          <span className="dot dot--g" />
          <span className="win__title">#design — Slack</span>
          <span className="win__pad" />
        </div>
        <div className="win__body">
          <aside className="win__side">
            {Array.from({ length: SIDE_ROWS }, (_, i) => (
              <span key={i} className={i === 1 ? "side__row side__row--on" : "side__row"} />
            ))}
          </aside>
          <div className="win__main">
            {MESSAGES.map(({ name, initials, avatar, lines }, i) => (
              <div key={i} className="msg">
                <span className={avatar ? `ava ${avatar}` : "ava"}>{initials}</span>
                <span className="msg__b">
                  <b>{name}</b>
                  {lines.map((width, j) => (
                    <i key={j} className={width || undefined} />
                  ))}
                </span>
              </div>
            ))}
            <div className="composer">
              <span className="composer__text">
                <span className="typed">{TRANSCRIPT}</span>
                <span className="caret" />
              </span>
              <span className="composer__send" />
            </div>
          </div>
        </div>
      </div>

      <div className="ov ov--key">
        <kbd>⌥</kbd>
        <kbd>Space</kbd>
      </div>

      {/* The compact recording card, laid out like the app's: a full-height
          level meter over the one control row that every HUD mode shows. */}
      <div className="ov ov--hud">
        <HudBars />
        <div className="hud__row">
          <span className="hud__t">0:04</span>
          <span className="hud__spacer" />
          <span className="hud__btn">
            Cancel <em>esc</em>
          </span>
          <span className="hud__btn hud__btn--primary">
            Finish <em>⌥Space</em>
          </span>
        </div>
      </div>

      <div className="ov ov--review">
        <p className="rv__head">
          <span>Transcript</span>
          <em>parakeet · local</em>
        </p>
        <p className="rv__text">
          Ship the release notes<u>,</u> then ping design<u>.</u>
        </p>
        <p className="rv__foot">
          <span className="rv__key">⏎</span>
          <span className="rv__hint">paste at cursor</span>
          <span className="rv__key rv__key--end">esc</span>
          <span className="rv__hint">discard</span>
        </p>
      </div>

      <div className="ov ov--toast">
        <Tick />
        Pasted at your cursor
      </div>
    </div>
  );
}

export function Story() {
  const [step, setStep] = useState(1);
  const beatRefs = useRef<Array<HTMLLIElement | null>>([]);

  useEffect(() => {
    const beats = beatRefs.current.filter((el): el is HTMLLIElement => el !== null);
    if (!beats.length) return;
    if (typeof IntersectionObserver === "undefined") {
      // No observer: show every beat at full contrast rather than leaving
      // beats 2-5 faint forever.
      for (const beat of beats) beat.classList.add("is-active");
      return;
    }

    // At a boundary two beats can share the band, so take the one nearest the
    // viewport centre.
    const observer = new IntersectionObserver(
      (entries) => {
        let best: HTMLElement | null = null;
        let bestDistance = Infinity;
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const rect = entry.boundingClientRect;
          const distance = Math.abs(rect.top + rect.height / 2 - window.innerHeight / 2);
          if (distance < bestDistance) {
            bestDistance = distance;
            best = entry.target as HTMLElement;
          }
        }
        const next = Number(best?.dataset.step);
        if (next) setStep(next);
      },
      { rootMargin: "-45% 0px -45% 0px", threshold: 0 },
    );

    for (const beat of beats) observer.observe(beat);
    return () => observer.disconnect();
  }, []);

  const railStyle = { "--p": `${((step - 1) / (BEATS.length - 1)) * 100}%` } as CSSProperties;

  return (
    <section className="story section--band" id="how-it-works" aria-labelledby="story-title">
      <div className="wrap">
        <div className="sec-head">
          <p className="kicker kicker--ch">
            <span className="kicker__n" aria-hidden="true">
              01
            </span>
            <span>Chapter one · five beats</span>
          </p>
          <h2 id="story-title">What happens when you speak.</h2>
          <p className="lede">
            One sentence, from the moment you press the key to the moment it appears in the field you were already
            typing in. Nothing is staged off-screen — this is the whole loop.
          </p>
        </div>

        <div className="story__rig">
          <ol className="beats">
            {BEATS.map(({ step: beatStep, title, body, note, art }, i) => (
              <li
                key={beatStep}
                ref={(el) => {
                  beatRefs.current[i] = el;
                }}
                className={step === beatStep ? "beat is-active" : "beat"}
                data-step={beatStep}
              >
                <p className="beat__no">Beat {String(beatStep).padStart(2, "0")}</p>
                <h3>{title}</h3>
                <div className="beat__art" aria-hidden="true">
                  {art}
                </div>
                <p>{body}</p>
                <p className="beat__note">{note}</p>
              </li>
            ))}
          </ol>

          <div className="stagecol" aria-hidden="true">
            <div className="rail" style={railStyle}>
              <span className="rail__line">
                <span className="rail__fill" />
              </span>
              {BEATS.map(({ step: beatStep }) => (
                <b
                  key={beatStep}
                  className={["rail__node", beatStep <= step ? "is-on" : "", beatStep === step ? "is-now" : ""]
                    .filter(Boolean)
                    .join(" ")}
                >
                  {beatStep}
                </b>
              ))}
            </div>

            <Stage step={step} />
          </div>
        </div>

        <p className="lede muted" style={{ marginTop: "clamp(24px, 4vw, 40px)" }}>
          Prefer push to talk? Switch to hold-to-record in Settings.{" "}
          <Link className="link" href={GUIDE_PATH}>
            Every setting is explained in the Mac setup guide
          </Link>
          .
        </p>
      </div>
    </section>
  );
}
