import { REPO_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";
import { StatusDot, type StatusKind } from "@/components/ui/status-dot";

type ColumnIndex = 0 | 1 | 2 | 3 | 4;

type CompareRow = {
  label: string;
  cells: [string, string, string, string, string];
  status: [StatusKind, StatusKind, StatusKind, StatusKind, StatusKind];
  footnotes?: Partial<Record<ColumnIndex, number>>;
};

const COLUMNS = ["VoiceToText", "Wispr Flow", "Superwhisper", "MacWhisper", "Apple Dictation"] as const;

const ROWS: CompareRow[] = [
  {
    label: "Price",
    cells: ["Free — no paid tiers", "Subscription required", "Subscription or one-time fee", "One-time purchase", "Free (built-in)"],
    status: ["ok", "no", "no", "no", "ok"],
    footnotes: { 1: 1, 2: 2, 3: 3 },
  },
  {
    label: "Open source",
    cells: ["Yes — on GitHub", "—", "—", "—", "—"],
    status: ["ok", "no", "no", "no", "no"],
  },
  {
    label: "Runs 100% offline",
    cells: ["On-device", "Cloud only", "On-device", "On-device", "On-device (English & select langs)"],
    status: ["ok", "no", "ok", "ok", "partial"],
  },
  {
    label: "No account required",
    cells: ["None required", "Account required", "Account required", "No account", "None required"],
    status: ["ok", "no", "no", "ok", "ok"],
  },
  {
    label: "Push-to-talk (hold key)",
    cells: ["⌥ Space — hold or toggle", "Customizable hold", "Customizable hold", "Pro (Global mode)", "Toggle only"],
    status: ["ok", "ok", "ok", "partial", "no"],
  },
  {
    label: "Works in any text field",
    cells: ["System-wide", "System-wide", "System-wide", "Pro only", "System-wide"],
    status: ["ok", "ok", "ok", "partial", "ok"],
  },
  {
    label: "Apple Neural Engine (Apple Silicon)",
    cells: ["Yes — Apple Silicon", "N/A — cloud-side inference", "Yes — Apple Silicon", "Yes — Apple Silicon", "Yes — Apple Silicon"],
    status: ["ok", "no", "ok", "ok", "ok"],
    footnotes: { 1: 4 },
  },
  {
    label: "Native macOS app (no Electron)",
    cells: ["SwiftUI native", "Electron-based", "SwiftUI native", "SwiftUI native", "Native"],
    status: ["ok", "no", "ok", "ok", "ok"],
  },
  {
    label: "Choice of local speech engine",
    cells: ["Whisper + Parakeet local · optional OpenAI/ElevenLabs cloud", "Single proprietary cloud model", "Multiple Whisper model sizes", "Multiple Whisper sizes (Pro)", "Apple model only"],
    status: ["ok", "no", "ok", "partial", "no"],
    footnotes: { 3: 5 },
  },
];

const FOOTNOTES = [
  "Wispr Flow is subscription-only; verify current pricing on the vendor site.",
  "Superwhisper pricing varies between subscription and one-time options — verify on the vendor site.",
  "MacWhisper Pro is sold as a one-time purchase, but price varies across sources ($69, $79.99, €59) — verify on the Gumroad product page.",
  "Wispr Flow runs inference in the cloud, so on-device Apple Neural Engine acceleration is not applicable.",
  "MacWhisper’s free tier ships a single Whisper engine; multiple model sizes require the Pro upgrade.",
];

function DesktopTable() {
  return (
    <div className="compare__frame" role="region" aria-label="Feature comparison between VoiceToText and competitors">
      <table className="compare__grid">
        <caption className="sr-only">
          Feature comparison between VoiceToText, Wispr Flow, Superwhisper, MacWhisper, and Apple Dictation
        </caption>
        <thead>
          <tr>
            <th scope="col" className="compare__head compare__head--row">Feature</th>
            <th scope="col" className="compare__head compare__head--ours">{COLUMNS[0]}</th>
            {COLUMNS.slice(1).map((c) => (
              <th key={c} scope="col" className="compare__head">{c}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {ROWS.map((row) => (
            <tr key={row.label}>
              <th scope="row" className="compare__row-label">{row.label}</th>
              {row.cells.map((cell, i) => {
                const fnId = row.footnotes?.[i as ColumnIndex];
                return (
                  <td key={i} className={`compare__cell${i === 0 ? " compare__cell--ours" : ""}`}>
                    <StatusDot kind={row.status[i]} />
                    {cell}
                    {fnId ? (
                      <sup>
                        <a href={`#fn-${fnId}`} aria-describedby="compare-footnotes-title">{fnId}</a>
                      </sup>
                    ) : null}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function MobileCards() {
  return (
    <div className="compare__mobile">
      {COLUMNS.map((col, colIdx) => (
        <details
          key={col}
          className={`compare__card${colIdx === 0 ? " compare__card--ours" : ""}`}
          open={colIdx === 0}
        >
          <summary className="compare__card-head">
            <span className="compare__card-title">
              <Icon name="chevron-down" className="compare__card-chevron" />
              <strong>{col}</strong>
            </span>
            {colIdx === 0 ? (
              <span className="chip chip--accent">
                <span className="chip__dot" aria-hidden="true" />
                Free &amp; open source
              </span>
            ) : null}
          </summary>
          <dl>
            {ROWS.map((row) => {
              const fnId = row.footnotes?.[colIdx as ColumnIndex];
              return (
                <div key={row.label} className="compare__card-row">
                  <dt>{row.label}</dt>
                  <dd>
                    <StatusDot kind={row.status[colIdx]} />
                    {row.cells[colIdx]}
                    {fnId ? (
                      <sup>
                        <a href={`#fn-${fnId}`} aria-describedby="compare-footnotes-title">{fnId}</a>
                      </sup>
                    ) : null}
                  </dd>
                </div>
              );
            })}
          </dl>
        </details>
      ))}
    </div>
  );
}

export function Compare() {
  return (
    <section className="section compare reveal" id="compare" aria-labelledby="compare-title">
      <div className="container">
        <p className="section__eyebrow">Compare</p>
        <h2 id="compare-title" className="section__title">
          VoiceToText vs. Wispr Flow, Superwhisper, MacWhisper, and Apple Dictation.
        </h2>
        <p className="section__deck">
          Same core idea — speech to text into any Mac app. Different terms: permanently free, no
          subscription, no account, offline by default, and source code you can read and audit.
        </p>

        <DesktopTable />
        <MobileCards />

        <h3 id="compare-footnotes-title" className="sr-only">Comparison table footnotes</h3>
        <ol className="compare__footnotes t-caption" role="list">
          {FOOTNOTES.map((text, i) => (
            <li key={i} id={`fn-${i + 1}`}>
              <sup>{i + 1}</sup> {text}
            </li>
          ))}
        </ol>
        <p className="compare__footnotes t-caption">
          Competitor details as of July 2026 — verify current pricing and capabilities on each
          vendor&rsquo;s site.
        </p>

        <p className="compare__links t-caption">
          <ExternalLink href={REPO_URL}>
            Audit the source code <Icon name="arrow-right" size="sm" />
          </ExternalLink>
          <span className="compare__sep">·</span>
          <ExternalLink href={REPO_URL}>
            Free &amp; open source <Icon name="arrow-right" size="sm" />
          </ExternalLink>
        </p>
      </div>
    </section>
  );
}
