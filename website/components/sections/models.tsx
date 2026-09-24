import Link from "next/link";
import type { CSSProperties } from "react";

import {
  cloudModels,
  formatPrice,
  formatQuality,
  joinNames,
  liveOnStopModelNames,
  liveTextModelNames,
  localModels,
  MODEL_CATALOG,
  type ModelFact,
  WHISPER_OFFLINE_NOTE,
} from "@/lib/app-facts";
import { countWord } from "@/lib/seo";

type MeterVars = CSSProperties & Record<"--q", string>;

/** How the app handles languages for a local model (it has no language picker). */
function localLanguages(model: ModelFact): string {
  return model.languagesInApp === "English"
    ? "English in VoiceToText"
    : `${model.languagesInApp}, detected automatically`;
}

/** One plain line on what a cloud model does differently, straight from the catalog flags. */
function cloudNote(model: ModelFact): string {
  if (model.diarize) return "Labels who said what — for conversations and files";
  if (model.live && model.liveTextCadence === "word by word") return "Text appears word by word as you speak — dictation only";
  if (model.live && model.liveTextCadence === "phrase by phrase") return "Text appears phrase by phrase, after each short pause — dictation only";
  if (model.live) return "Streams while you speak; the text appears only when you stop — dictation only";
  return "Dictation, conversations and files";
}

function Quality({ model }: { model: ModelFact }) {
  const style: MeterVars = { "--q": `${model.quality * 10}%` };
  return (
    <span className="qmeter">
      <span className="qmeter__val" aria-hidden="true">{formatQuality(model)}</span>
      <span className="sr-only">
        Quality score {model.qualityApprox ? "about " : ""}
        {model.quality.toFixed(1)} out of 10
      </span>
      <span className="qmeter__bar" aria-hidden="true">
        <i style={style} />
      </span>
    </span>
  );
}

export function Models() {
  const local = localModels();
  const cloud = cloudModels();

  return (
    <section className="section section--band" id="models" aria-labelledby="models-title">
      <div className="wrap">
        <div className="sec-head">
          <p className="kicker kicker--ch">
            <span className="kicker__n" aria-hidden="true">04</span>
            <span>Chapter four · {MODEL_CATALOG.length} models</span>
          </p>
          <h2 id="models-title">Pick the speech-to-text model that fits the job.</h2>
          <p className="lede">
            {countWord(local.length)} models run on your Mac, so your audio never leaves it, and Parakeet, the
            default, keeps working with the network off. {countWord(cloud.length)} more are optional cloud models
            on your own API key. Switch in Settings → Models whenever the trade-off changes — a quick note is not
            the same job as an hour-long call.
          </p>
        </div>

        <h3 className="models__h">On this Mac · free, audio stays local</h3>
        <p className="axis" aria-hidden="true">
          <span />
          <span>Model</span>
          <span>Languages</span>
          <span>Quality score</span>
          <span>Best for</span>
        </p>
        <ul className="models" role="list">
          {local.map((model, i) => (
            <li className="model" key={model.id}>
              <span className="model__n" aria-hidden="true">{String(i + 1).padStart(2, "0")}</span>
              <span className="model__name">
                {model.name}
                {model.isDefault ? <span className="badge">Default</span> : null}
                {model.chip ? (
                  <span className="tag"><i aria-hidden="true" />{model.chip}</span>
                ) : null}
              </span>
              <span className="model__lang">{localLanguages(model)}</span>
              <Quality model={model} />
              <span className="model__note">{model.bestFor}</span>
            </li>
          ))}
        </ul>
        <p className="models__src">
          <strong>Offline?</strong> {WHISPER_OFFLINE_NOTE}
        </p>

        <div className="cloud">
          <div className="cloud__head">
            <h3>Optional cloud models</h3>
            <p className="muted">
              Bring your own API key · billed by the provider · off unless you choose one
            </p>
          </div>
          <p className="cloud__lede">
            Audio goes straight from your Mac to OpenAI or ElevenLabs, which detect the language on their side (99+
            and 90+ languages). <span className="badge badge--live">Live</span> models stream your audio while you
            speak. {joinNames(liveTextModelNames("word by word"))} shows the words one by one in the dictation HUD;{" "}
            {joinNames(liveTextModelNames("phrase by phrase"))} add each phrase after a short pause;{" "}
            {joinNames(liveOnStopModelNames())} shows its text only when you stop.
          </p>
          <ul className="cloud__grid" role="list">
            {cloud.map((model) => (
              <li className="cm" key={model.id}>
                <span className="cm__name">
                  {model.name}
                  {model.live ? <span className="badge badge--live">Live</span> : null}
                  {model.chip === "Most accurate" ? (
                    <span className="tag"><i aria-hidden="true" />{model.chip}</span>
                  ) : null}
                </span>
                <span className="cm__meta">
                  <span>{model.provider}</span>
                  <span>{formatPrice(model)}</span>
                </span>
                <Quality model={model} />
                <span className="cm__note">{cloudNote(model)}</span>
              </li>
            ))}
          </ul>
        </div>

        <p className="models__src">
          Quality scores (1–10) are derived from third-party published word error rates — Artificial Analysis AA-WER
          and the Open ASR Leaderboard, September 2026 snapshot — not from VoiceToText’s own tests. “≈” marks a score
          built on indirect evidence. The app shows the same numbers in Settings → Models, with filters and sorting.
          Prices are the providers’ list prices per hour of audio.
        </p>
        <p className="models__src">
          Not sure which local model to start with?{" "}
          <Link className="link" href="/whisper-vs-parakeet-mac">
            Compare Whisper and Parakeet on Mac
          </Link>
          .
        </p>
      </div>
    </section>
  );
}
