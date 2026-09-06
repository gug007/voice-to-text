import type { ReactNode } from "react";
import Link from "next/link";

import { GUIDE_PATH } from "@/lib/constants";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";

type Step = {
  title: ReactNode;
  body: ReactNode;
};

const STEPS: Step[] = [
  {
    title: <>Press <HotkeyCombo /></>,
    body: "A small HUD with a live waveform appears over whatever you are doing. No window to open, and Esc cancels at any time.",
  },
  {
    title: "Say what you mean",
    body: "Full sentences, casual or technical. Punctuation is inferred, and with a streaming model the words appear as you speak.",
  },
  {
    title: "Press again to review and paste",
    body: "The transcript pops up for a quick edit. Hit Return and it lands at the cursor of the app you are in. Turn review off and it pastes instantly.",
  },
];

export function HowItWorks() {
  return (
    <section className="section how" id="how-it-works" aria-labelledby="how-title">
      <div className="container">
        <div className="section__head">
          <h2 id="how-title" className="section__title">Three steps, from inside any app.</h2>
          <p className="section__deck">
            The shortcut works wherever your cursor is. Prefer push to talk? Switch to hold-to-record in Settings.
          </p>
        </div>
        <ol className="how__steps" role="list">
          {STEPS.map(({ title, body }, i) => (
            <li key={i} className="how__step">
              <span className="how__index" aria-hidden="true">{i + 1}</span>
              <h3 className="how__title">{title}</h3>
              <p className="how__body">{body}</p>
            </li>
          ))}
        </ol>
        <p className="how__footer">
          Want every setting explained? <Link className="link" href={GUIDE_PATH}>Read the complete Mac setup guide</Link>.
        </p>
      </div>
    </section>
  );
}
