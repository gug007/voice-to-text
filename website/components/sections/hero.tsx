import { DMG_URL } from "@/lib/constants";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";
import { WaveBars } from "@/components/ui/wave-bars";

const META = ["Signed & notarized", "Direct DMG", "No app telemetry"];

export function Hero() {
  return (
    <section className="section hero" id="top" aria-labelledby="hero-title">
      <WaveBars />
      <div className="container hero__inner">
        <p className="hero__eyebrow">
          <span className="hero__eyebrow-dot" aria-hidden="true" />
          Free · Open source · macOS
        </p>
        <h1 id="hero-title" className="hero__title">
          Voice to text for Mac.
          <br />
          <span className="hero__title-accent">Speak. It types. Anywhere.</span>
        </h1>
        <p className="hero__lead">
          Press <HotkeyCombo /> to dictate into any app. Runs locally on Apple Silicon — free, open source,
          and no account required.
        </p>
        <div className="hero__ctas">
          <a
            className="btn btn--primary btn--lg"
            href={DMG_URL}
            data-analytics-event="download_click"
            data-analytics-placement="home_hero"
          >
            <Icon name="download" />
            <span>Download for Mac — free</span>
          </a>
          <a className="btn btn--secondary btn--lg" href="#demo">
            <span>See it in action</span>
            <Icon name="arrow-right" />
          </a>
        </div>
        <p className="hero__meta">
          {META.map((item, i) => (
            <span key={item} style={{ display: "inline-flex", alignItems: "center", gap: "var(--space-3)" }}>
              {item}
              {i < META.length - 1 ? <span className="hero__meta-sep" aria-hidden="true" /> : null}
            </span>
          ))}
        </p>
        <p className="hero__meta-sub t-caption">
          Built for Apple Silicon (M1 or newer) · Requires macOS 15.0 or later.
        </p>
        <p className="hero__subcopy">
          Speak in Notes, Slack, Mail, Notion, ChatGPT, a terminal, or any other text field. Review the
          result before it types, or turn on instant paste.
        </p>
      </div>
    </section>
  );
}
