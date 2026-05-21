import type { ReactNode } from "react";

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
    title: <>Hold <HotkeyCombo /></>,
    body: <>Hold <HotkeyCombo />, speak, release — words appear at the cursor. Nothing leaves the Mac.</>,
  },
  {
    index: "02",
    icon: "mic",
    title: "Speak naturally",
    body: "Full sentences, paragraphs, casual or technical. Punctuation is inferred; you can add it yourself if you prefer.",
  },
  {
    index: "03",
    icon: "arrow-right",
    title: "Release — words are typed",
    body: "Let go of the keys. Your text is typed straight into the focused app at the cursor.",
  },
];

export function HowItWorks() {
  return (
    <section className="section how reveal" id="how-it-works" aria-labelledby="how-title">
      <div className="container">
        <p className="section__eyebrow">Three steps</p>
        <h2 id="how-title" className="section__title">
          How to use voice to text on Mac and MacBook.
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
      </div>
    </section>
  );
}
