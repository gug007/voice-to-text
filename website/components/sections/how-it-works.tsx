import type { ReactNode } from "react";
import Link from "next/link";

import { GUIDE_PATH } from "@/lib/constants";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon, type IconName } from "@/components/ui/icon";

type Step = {
  index: string;
  icon: IconName;
  title: ReactNode;
  body: ReactNode;
};

const STEPS: Step[] = [
  {
    index: "01",
    icon: "keyboard",
    title: <>Press <HotkeyCombo /></>,
    body: <>A floating HUD with a live waveform appears — from any app, no window switch. Esc cancels anytime. Prefer push-to-talk? Switch to hold-to-record in Settings.</>,
  },
  {
    index: "02",
    icon: "mic",
    title: "Speak naturally",
    body: "Full sentences, paragraphs, casual or technical. Punctuation is inferred; with a streaming model the words appear live as you speak.",
  },
  {
    index: "03",
    icon: "arrow-right",
    title: "Press again — review, paste",
    body: "The transcript pops up for a quick edit — hit Return and it lands at the cursor of the focused app. Turn review off and it pastes instantly.",
  },
];

export function HowItWorks() {
  return (
    <section className="section how reveal" id="how-it-works" aria-labelledby="how-title">
      <div className="container">
        <p className="section__eyebrow">Three steps</p>
        <h2 id="how-title" className="section__title">
          Start dictating in any Mac app in three steps.
        </h2>
        <ul className="how__steps" role="list">
          {STEPS.map(({ index, icon, title, body }) => (
            <li key={index} className="how__step">
              <span className="how__index">{index}</span>
              <span className="how__icon" aria-hidden="true"><Icon name={icon} size="lg" /></span>
              <h3 className="how__title">{title}</h3>
              <p className="how__body">{body}</p>
            </li>
          ))}
        </ul>
        <div className="how__footer">
          <Link className="btn btn--secondary" href={GUIDE_PATH}>
            <span>Read the complete Mac setup guide</span>
            <Icon name="arrow-right" />
          </Link>
        </div>
      </div>
    </section>
  );
}
