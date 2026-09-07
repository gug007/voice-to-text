import type { ReactNode } from "react";
import Link from "next/link";

import { GUIDE_PATH } from "@/lib/constants";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";

const HUD_ART_BARS = 22;

function HudArt() {
  return (
    <div className="flow__hud">
      <div className="flow__hud-bars">
        {Array.from({ length: HUD_ART_BARS }, (_, i) => (
          <span key={i} style={{ height: `${(20 + 70 * Math.abs(Math.sin(i * 0.6 + 0.9))).toFixed(0)}%` }} />
        ))}
      </div>
      <div className="flow__hud-foot">
        <span className="flow__hud-timer">0:02</span>
        <span>⌥ Space to stop</span>
      </div>
    </div>
  );
}

function StreamArt() {
  return (
    <div className="flow__stream">
      Punctuation is inferred, and words appear as you speak
      <span className="flow__caret" />
    </div>
  );
}

function ReviewArt() {
  return (
    <div className="flow__review">
      <p>Ship the onboarding update on Tuesday.</p>
      <div className="flow__review-foot">
        <kbd className="keycap">Return</kbd> Paste at cursor
      </div>
    </div>
  );
}

type Step = {
  title: ReactNode;
  body: string;
  art: ReactNode;
};

const STEPS: Step[] = [
  {
    title: <>Press <HotkeyCombo /></>,
    body: "A small HUD with a live waveform appears over whatever you are doing. No window to open, and Esc cancels at any time.",
    art: <HudArt />,
  },
  {
    title: "Say what you mean",
    body: "Full sentences, casual or technical. Punctuation is inferred, and with a streaming model the words appear as you speak.",
    art: <StreamArt />,
  },
  {
    title: "Review, then it types",
    body: "The transcript pops up for a quick edit. Hit Return and it lands at the cursor of the app you are in. Turn review off and it pastes instantly.",
    art: <ReviewArt />,
  },
];

export function HowItWorks() {
  return (
    <section className="section section--band flow" id="how-it-works" aria-labelledby="how-title">
      <div className="container">
        <div className="section__head section__head--center">
          <h2 id="how-title" className="section__title">What happens when you speak.</h2>
          <p className="section__deck">
            The whole dictation flow lives in one shortcut. No window to find, no app to switch to.
          </p>
        </div>
        <ol className="flow__steps" role="list">
          {STEPS.map(({ title, body, art }, i) => (
            <li key={i} className="flow__step">
              <div className="flow__art" aria-hidden="true">{art}</div>
              <div className="flow__body">
                <span className="flow__index">Step {i + 1}</span>
                <h3 className="flow__title">{title}</h3>
                <p className="flow__text">{body}</p>
              </div>
            </li>
          ))}
        </ol>
        <p className="flow__footer">
          Prefer push to talk? Switch to hold-to-record in Settings. Esc cancels at any time.{" "}
          <Link className="link" href={GUIDE_PATH}>Every setting is explained in the Mac setup guide</Link>.
        </p>
      </div>
    </section>
  );
}
