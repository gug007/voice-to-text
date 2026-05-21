import type { CSSProperties } from "react";

import { DMG_URL, REPO_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";

const WAVE_BAR_COUNT = 64;

function WaveBars() {
  return (
    <div className="dictation-wave" aria-hidden="true">
      <div className="bars">
        {Array.from({ length: WAVE_BAR_COUNT }, (_, i) => (
          <i key={i} style={{ "--i": i } as CSSProperties & Record<"--i", number>} />
        ))}
      </div>
    </div>
  );
}

export function Hero() {
  return (
    <section className="section hero reveal" id="top" aria-labelledby="hero-title">
      <WaveBars />
      <div className="container hero__inner">
        <p className="hero__eyebrow">Free · Open source · macOS</p>
        <h1 id="hero-title" className="hero__title">
          Voice to Text for Mac. Free. Offline.
        </h1>
        <p className="hero__lead">
          Push-to-talk dictation for Mac. On-device. No account. Free.
        </p>
        <p className="hero__subcopy">
          Hold <HotkeyCombo />, speak, release — your words land at the cursor in Notes, Slack, Mail,
          Notion, ChatGPT, or any Mac app, transcribed offline on the Apple Neural Engine.
        </p>
        <div className="hero__ctas">
          <a className="btn btn--primary btn--lg" href={DMG_URL} download>
            <Icon name="download" />
            <span>Get it free — download for Mac</span>
          </a>
          <ExternalLink className="btn btn--secondary" href={REPO_URL}>
            <Icon name="github" />
            <span>View source on GitHub</span>
          </ExternalLink>
        </div>
        <p className="hero__meta">Free · Open source · No account · No subscription</p>
        <p className="hero__meta-sub t-caption">
          Requires macOS 14 Sonoma+ · Apple Silicon only (M1+) · Intel Macs not supported.
        </p>
      </div>
    </section>
  );
}
