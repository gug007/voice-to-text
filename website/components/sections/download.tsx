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
    body: <>Drag <strong>VoiceToText</strong> to <code className="code-inline">/Applications</code>. It takes five seconds.</>,
  },
  {
    title: "Launch the app",
    body: "The default local model (Parakeet TDT v3) downloads itself. No setup, no account.",
  },
  {
    title: "Grant Microphone and Accessibility",
    body: "A one-time prompt. The mic hears you, and Accessibility types into whatever app you are in. Revoke either at any time in System Settings.",
  },
  {
    title: <>Press <HotkeyCombo />, speak, press again</>,
    body: "Review the transcript, hit Return, and it lands at the cursor. Prefer hold-to-talk? One switch in Settings.",
  },
];

export function Download() {
  return (
    <section className="section download" id="download" aria-labelledby="download-title">
      <div className="container download__inner">
        <div className="download__glow" aria-hidden="true" />
        <div className="download__plate">
          <h2 id="download-title" className="section__title">
            Download VoiceToText for Mac.
          </h2>
          <p className="section__deck">
            Free, signed and notarized, and served straight from GitHub Releases. Requires macOS 15 or
            later on Apple Silicon.
          </p>
          <div className="download__ctas">
            <a
              className="btn btn--primary btn--lg"
              href={DMG_URL}
              data-analytics-event="download_click"
              data-analytics-placement="home_footer"
            >
              <Icon name="download" />
              <span>Download for Mac</span>
            </a>
            <ExternalLink className="btn btn--secondary btn--lg" href={RELEASES_URL}>
              <Icon name="github" />
              <span>All releases on GitHub</span>
            </ExternalLink>
          </div>
          <p className="download__meta">Updates are built in. The app checks GitHub Releases daily and installs new versions in place.</p>
          <ol className="download__steps" role="list">
            {STEPS.map(({ title, body }, i) => (
              <li key={i} className="download__step">
                <span className="download__step-num" aria-hidden="true">{i + 1}</span>
                <div>
                  <h3 className="download__step-title">{title}</h3>
                  <p className="download__step-body">{body}</p>
                </div>
              </li>
            ))}
          </ol>
          <p className="download__perms t-caption">
            <strong>Why two permissions?</strong> Microphone lets the app hear you. Accessibility lets it type
            into whatever app you are in. Both stay on the device.
          </p>
          <p className="download__reqs t-caption">
            <strong>Requirements:</strong> macOS 15.0 or later and an Apple Silicon Mac (M1 or newer).
          </p>
        </div>
      </div>
    </section>
  );
}
