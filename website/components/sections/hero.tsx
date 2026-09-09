import { DMG_URL } from "@/lib/constants";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";
import { WaveBars } from "@/components/ui/wave-bars";

const TRUST = [
  "Free · source on GitHub",
  "Works fully offline",
  "No account, no app telemetry",
  "Signed & notarized",
  "macOS 15+ · Apple Silicon",
];

function Tick() {
  return (
    <svg
      className="tick"
      viewBox="0 0 12 12"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.9"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M1.8 6.4l2.7 2.7L10.2 3" />
    </svg>
  );
}

export function Hero() {
  return (
    <section className="hero" id="top" aria-labelledby="hero-title">
      <WaveBars />
      <div className="hero__content">
        <h1 id="hero-title" className="hero__title">
          Voice to text for Mac.
          <br />
          <span className="hero__title-accent">Speak. It types. Anywhere.</span>
        </h1>
        <p className="hero__sub">
          Press <HotkeyCombo /> in any app, say what you mean, and the words land at your cursor. Transcription runs
          on-device on Apple Silicon — no account, no subscription, no servers of ours in the middle.
        </p>
        <div className="hero__cta">
          <a
            className="btn btn--primary btn--lg"
            href={DMG_URL}
            data-analytics-event="download_click"
            data-analytics-placement="home_hero"
          >
            <Icon name="download" />
            <span>Download for Mac — free</span>
          </a>
          <a className="btn btn--ghost btn--lg" href="#how-it-works">
            <span>Watch a sentence travel</span>
          </a>
        </div>
        <ul className="hero__trust">
          {TRUST.map((item) => (
            <li key={item}>
              <Tick />
              {item}
            </li>
          ))}
        </ul>
      </div>
      <p className="hero__scroll" aria-hidden="true">
        Scroll
        <span />
      </p>
    </section>
  );
}
