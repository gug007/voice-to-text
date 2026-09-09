import Link from "next/link";

type Model = {
  n: string;
  name: string;
  /** Shown as a small badge beside the name (the default model only). */
  badge?: string;
  tag: string;
  note: string;
};

const MODELS: Model[] = [
  {
    n: "01",
    name: "Parakeet TDT v3",
    badge: "Default",
    tag: "Fastest",
    note: "Downloads on first launch and is the fastest on-device option. What you get if you change nothing.",
  },
  {
    n: "02",
    name: "Whisper Large v3",
    tag: "Most accurate",
    note: "The most accurate offline option, for accents, crosstalk and generally tough audio.",
  },
  {
    n: "03",
    name: "Whisper Large v3 Turbo",
    tag: "Best balance",
    note: "Near-Large accuracy at a fraction of the latency. The pick if you can’t decide.",
  },
  {
    n: "04",
    name: "Whisper Small",
    tag: "Light",
    note: "A middle ground that keeps older Apple Silicon Macs comfortable.",
  },
  {
    n: "05",
    name: "Whisper Base",
    tag: "Lighter",
    note: "A small download for quick everyday notes and short messages.",
  },
  {
    n: "06",
    name: "Whisper Tiny",
    tag: "Smallest",
    note: "For space-constrained Macs. Instant, with a minimal footprint on disk.",
  },
];

const CLOUD_MODELS = [
  { name: "GPT-4o Transcribe", vendor: "OpenAI" },
  { name: "GPT-4o Mini Transcribe", vendor: "OpenAI" },
  { name: "GPT Transcribe", vendor: "OpenAI" },
  { name: "Scribe v2 Realtime", vendor: "ElevenLabs" },
] as const;

export function Models() {
  return (
    <section className="section section--band" id="models" aria-labelledby="models-title">
      <div className="wrap">
        <div className="sec-head">
          <p className="kicker kicker--ch">
            <span className="kicker__n" aria-hidden="true">03</span>
            <span>Chapter three · six local engines</span>
          </p>
          <h2 id="models-title">Pick the speech-to-text model that fits your Mac.</h2>
          <p className="lede">
            All six download once and then work with the network off. Swap between them in Settings
            whenever the trade-off changes — a quick note on a MacBook Air is not the same job as a
            noisy interview recording.
          </p>
        </div>

        <p className="axis" aria-hidden="true">
          <span />
          <span>Model</span>
          <span>Best for</span>
          <span>What the note says</span>
        </p>
        <ul className="models" role="list">
          {MODELS.map(({ n, name, badge, tag, note }) => (
            <li className="model" key={name}>
              <span className="model__n">{n}</span>
              <span className="model__name">
                {name}
                {badge ? <span className="badge"><span className="sr-only">Rated: </span>{badge}</span> : null}
              </span>
              <span>
                <span className="tag"><i aria-hidden="true" />{tag}</span>
              </span>
              <span className="model__note">{note}</span>
            </li>
          ))}
        </ul>

        <div className="cloud">
          <div className="cloud__head">
            <h3>Optional cloud models</h3>
            <p className="muted">
              Settings → Models · bring your own API key · off unless you turn it on
            </p>
          </div>
          <div className="cloud__chips">
            {CLOUD_MODELS.map(({ name, vendor }) => (
              <span className="chip" key={name}>{name} <em>{vendor}</em></span>
            ))}
          </div>
          <p className="muted">
            Not sure which local engine to start with?{" "}
            <Link className="link" href="/whisper-vs-parakeet-mac">
              Compare Whisper and Parakeet on Mac
            </Link>
            .
          </p>
        </div>
      </div>
    </section>
  );
}
