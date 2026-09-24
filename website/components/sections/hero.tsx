import { HeroStage } from "@/components/hero-stage";
import { DownloadButton } from "@/components/ui/download-button";
import { ExternalLink } from "@/components/ui/external-link";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { WaveBars } from "@/components/ui/wave-bars";
import type { LatestRelease } from "@/lib/release";

const TRUST = [
  "Free · source on GitHub",
  "Works offline by default",
  "No account, no app telemetry",
  "Signed & notarized",
  "macOS 15+ · Apple Silicon",
];

/** "2026-09-22" → "Sep 22, 2026": short enough to keep the release line on one row on a phone. */
function shortDate(iso: string): string {
  return new Intl.DateTimeFormat("en-US", { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" }).format(
    new Date(`${iso}T00:00:00Z`),
  );
}

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

export function Hero({ release }: { release: LatestRelease }) {
  return (
    <section className="hero hero--stage" id="top" aria-labelledby="hero-title">
      <div className="hero__top">
        <WaveBars />
        <div className="hero__content">
          <h1 id="hero-title" className="hero__title">
            <span className="hero__keep">Voice to text</span> <span className="hero__keep">for Mac.</span>{" "}
            <br />
            <span className="hero__title-accent">Speak. It types. Anywhere.</span>
          </h1>
          <p className="hero__sub">
            Press <HotkeyCombo /> in any app, speak, and your words are pasted at your cursor. Record a call or
            drop in a file to get a transcript, plus optional AI summaries and action items.
          </p>
          <div className="hero__cta">
            <DownloadButton placement="home_hero" />
            <a className="btn btn--ghost btn--lg" href="#demo">
              <span>Watch the 20-second demo</span>
            </a>
          </div>
          <p className="hero__release">
            <span>{release.tag}</span>
            <span aria-hidden="true">&middot;</span>
            <span>
              Released <time dateTime={release.publishedAt}>{shortDate(release.publishedAt)}</time>
            </span>
            <span aria-hidden="true">&middot;</span>
            <ExternalLink
              className="link"
              href={release.url}
              data-analytics-event="github_outbound"
              data-analytics-placement="home_hero_release"
            >
              Release notes
            </ExternalLink>
          </p>
        </div>
      </div>

      <div className="hero__below">
        <ul className="hero__trust">
          {TRUST.map((item) => (
            <li key={item}>
              <Tick />
              {item}
            </li>
          ))}
        </ul>
        <HeroStage />
      </div>
    </section>
  );
}
