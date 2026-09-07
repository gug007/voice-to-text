import { DMG_URL } from "@/lib/constants";
import { HeroStage } from "@/components/hero-stage";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";
import { WaveBars } from "@/components/ui/wave-bars";

const META = ["Signed & notarized", "No app telemetry", "Apple Silicon · macOS 15+"];

export function Hero() {
  return (
    <section className="section hero hero--stage" id="top" aria-labelledby="hero-title">
      <WaveBars />
      <div className="container hero__inner">
        <p className="hero__eyebrow">
          <span className="hero__eyebrow-dot" aria-hidden="true" />
          Free · Source on GitHub · macOS
        </p>
        <h1 id="hero-title" className="hero__title">
          Voice to text for Mac.
          <br />
          <span className="hero__title-accent">Speak. It types. Anywhere.</span>
        </h1>
        <p className="hero__lead">
          Press <HotkeyCombo /> to dictate into any app. Local on Apple Silicon, free, no account.
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
            <span>Watch the demo</span>
          </a>
        </div>
        <HeroStage />
        <p className="hero__meta">
          {META.map((item, i) => (
            <span key={item} style={{ display: "inline-flex", alignItems: "center", gap: "var(--space-3)" }}>
              {item}
              {i < META.length - 1 ? <span className="hero__meta-sep" aria-hidden="true" /> : null}
            </span>
          ))}
        </p>
      </div>
    </section>
  );
}
