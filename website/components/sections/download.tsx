import type { ReactNode } from "react";

import { DMG_URL, RELEASES_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";

type Step = {
  title: ReactNode;
  body: ReactNode;
};

const STEPS: Step[] = [
  {
    title: "Open the DMG",
    body: <>Drag <strong>VoiceToText</strong> to <code className="code-inline">/Applications</code>. Takes 5 seconds.</>,
  },
  {
    title: "Launch the app",
    body: "It lives in the menu bar.",
  },
  {
    title: "Grant Microphone and Accessibility",
    body: "One-time prompt — mic hears you, accessibility types into whatever app you’re in. Revoke anytime in System Settings.",
  },
  {
    title: <>Hold <HotkeyCombo />, speak, release.</>,
    body: "Your words are typed at the cursor.",
  },
];

export function Download() {
  return (
    <section className="section download reveal" id="download" aria-labelledby="download-title">
      <div className="container download__inner">
        <p className="section__eyebrow">Ready to dictate</p>
        <h2 id="download-title" className="section__title">
          Download VoiceToText — voice to text for macOS.
        </h2>
        <p className="section__deck">
          One DMG. Drag to Applications. Grant Microphone and Accessibility. Hold <HotkeyCombo /> and speak.
        </p>
        <div className="download__ctas">
          <a className="btn btn--primary btn--lg" href={DMG_URL} download>
            <Icon name="download" />
            <span>Get it free — download the DMG</span>
          </a>
          <ExternalLink className="btn btn--secondary btn--lg" href={RELEASES_URL}>
            <Icon name="github" />
            <span>See all releases on GitHub</span>
          </ExternalLink>
        </div>
        <p className="download__meta t-mono">Free · Open source · macOS 14+ · Apple Silicon</p>
        <ol className="download__steps">
          {STEPS.map(({ title, body }, i) => (
            <li key={i} className="download__step">
              <span className="download__step-num">{i + 1}</span>
              <div>
                <h3 className="download__step-title">{title}</h3>
                <p className="download__step-body">{body}</p>
              </div>
            </li>
          ))}
        </ol>
        <p className="download__perms t-caption">
          <strong>Why two permissions?</strong> Microphone lets the app hear you. Accessibility lets it type
          into whatever app you’re in. Both stay on-device. Revoke anytime in System Settings.
        </p>
        <p className="download__reqs t-caption">
          <strong>Requirements:</strong> macOS 14 Sonoma or later · Apple Silicon (M1 or newer).
        </p>
      </div>
    </section>
  );
}
