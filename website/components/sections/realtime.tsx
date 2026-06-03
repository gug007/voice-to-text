import { RealtimeDemo } from "@/components/realtime-demo";

export function Realtime() {
  return (
    <section className="section realtime reveal" id="realtime" aria-labelledby="realtime-title">
      <div className="container">
        <p className="section__eyebrow">Real-time</p>
        <h2 id="realtime-title" className="section__title">Watch your words appear as you speak.</h2>
        <p className="section__deck">
          Pick a streaming engine — <strong>Scribe v2 Realtime</strong> (ElevenLabs) or{" "}
          <strong>GPT-4o Transcribe Realtime</strong> (OpenAI) — and your speech is transcribed live,
          word by word, then pasted at the cursor when you finish. No waiting for the whole clip.
        </p>
        <RealtimeDemo />
      </div>
    </section>
  );
}
