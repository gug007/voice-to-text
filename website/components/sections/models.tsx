import Link from "next/link";

type Model = {
  name: string;
  tag: string;
  tone: "accent" | "ready" | "muted";
  body: string;
};

const MODELS: Model[] = [
  {
    name: "Parakeet TDT v3",
    tag: "Fastest",
    tone: "accent",
    body: "The default. Downloads itself on first launch and runs fastest on-device.",
  },
  {
    name: "Whisper Large v3",
    tag: "Most accurate",
    tone: "ready",
    body: "The most accurate offline option for tough audio.",
  },
  {
    name: "Whisper Large v3 Turbo",
    tag: "Best balance",
    tone: "muted",
    body: "Near-Large accuracy at a fraction of the latency.",
  },
  {
    name: "Whisper Small",
    tag: "Light",
    tone: "muted",
    body: "A solid middle ground for older Apple Silicon Macs.",
  },
  {
    name: "Whisper Base",
    tag: "Lighter",
    tone: "muted",
    body: "Small download, quick transcription for everyday notes.",
  },
  {
    name: "Whisper Tiny",
    tag: "Smallest",
    tone: "muted",
    body: "For space-constrained Macs. Instant, minimal footprint.",
  },
];

export function Models() {
  return (
    <section className="section models" id="models" aria-labelledby="models-title">
      <div className="container">
        <div className="section__head">
          <h2 id="models-title" className="section__title">Pick the speech-to-text model that fits your Mac.</h2>
          <p className="section__deck">
            Six local models, downloaded once. Cloud engines are optional and use your own API key.
          </p>
        </div>
        <ul className="models__grid" role="list">
          {MODELS.map(({ name, tag, tone, body }) => (
            <li key={name} className="models__item">
              <div className="models__head">
                <h3 className="models__name">{name}</h3>
                <span className={`models__tag models__tag--${tone}`}>{tag}</span>
              </div>
              <p className="models__body">{body}</p>
            </li>
          ))}
        </ul>
        <p className="models__note">
          Highest accuracy across accents and jargon: bring your own key and switch to GPT-4o Transcribe
          (OpenAI) or Scribe v2 Realtime (ElevenLabs) in <em>Settings → Models</em>.{" "}
          <Link className="link" href="/whisper-vs-parakeet-mac">Compare Whisper and Parakeet on Mac</Link>.
        </p>
      </div>
    </section>
  );
}
