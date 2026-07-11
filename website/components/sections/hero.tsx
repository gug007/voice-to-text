import { DMG_URL, REPO_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";
import { WaveBars } from "@/components/ui/wave-bars";

const META = ["Free", "Open source", "No account", "No subscription"];

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
          <span className="hero__title-accent">Free. Offline.</span>
        </h1>
        <p className="hero__lead">
          Hotkey dictation that types straight into any Mac app — on-device, no account, no subscription.
        </p>
        <div className="hero__ctas">
          <a className="btn btn--primary btn--lg" href={DMG_URL}>
            <Icon name="download" />
            <span>Get it free — download for Mac</span>
          </a>
          <ExternalLink className="btn btn--secondary btn--lg" href={REPO_URL}>
            <Icon name="github" />
            <span>View source on GitHub</span>
          </ExternalLink>
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
          Requires macOS 26.4+ · Apple Silicon only (M1+) · Intel Macs not supported.
        </p>
        <p className="hero__subcopy">
          Press <HotkeyCombo />, speak, press again — your words land at the cursor in Notes, Slack, Mail,
          Notion, ChatGPT, or any Mac app, transcribed offline on the Apple Neural Engine. Prefer
          push-to-talk? Switch to hold-to-record in Settings.
        </p>
      </div>
    </section>
  );
}
