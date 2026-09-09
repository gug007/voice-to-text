import { ExternalLink } from "@/components/ui/external-link";
import { Icon, type IconName } from "@/components/ui/icon";
import { REPO_URL } from "@/lib/constants";

type PrivacyCard = {
  icon: IconName;
  title: string;
  body: string;
};

const CARDS: PrivacyCard[] = [
  {
    icon: "bolt",
    title: "The engines run on the Neural Engine",
    body: "WhisperKit and FluidAudio run Whisper and Parakeet directly on Apple Silicon. Six local models, downloaded once, then yours offline forever.",
  },
  {
    icon: "cloud",
    title: "Cloud is opt-in, with your own key",
    body: "Choose a cloud model and the audio goes straight from your Mac to OpenAI or ElevenLabs using your key. VoiceToText is never in that path — there are no first-party servers to be in it.",
  },
  {
    icon: "lock",
    title: "Two permissions, both explainable",
    body: "Microphone, so it can hear you. Accessibility, because that is the only way macOS lets one app type into another. Only if you rebind the shortcut to Right Control on its own does macOS also ask for Input Monitoring.",
  },
];

type LedgerRow = {
  label: string;
  note: string;
  tag: string;
  /** A row that does happen (an icon and a green tag) vs. one that never does. */
  happens: boolean;
  icon?: IconName;
};

const LEDGER: LedgerRow[] = [
  {
    happens: true,
    icon: "download",
    label: "Model download",
    note: "once per model, then never again",
    tag: "once",
  },
  {
    happens: true,
    icon: "cloud",
    label: "Update check",
    note: "against GitHub Releases",
    tag: "daily",
  },
  {
    happens: false,
    label: "Your audio",
    note: "transcribed on the Neural Engine",
    tag: "never leaves",
  },
  {
    happens: false,
    label: "Your transcripts",
    note: "kept on device, in History",
    tag: "never leaves",
  },
  {
    happens: false,
    label: "App telemetry",
    note: "no analytics SDK, no crash pings",
    tag: "none",
  },
  {
    happens: false,
    label: "Accounts & sync",
    note: "no sign-in exists",
    tag: "none",
  },
];

export function Features() {
  return (
    <section className="section" id="features" aria-labelledby="features-title">
      <div className="wrap">
        <div className="sec-head">
          <p className="kicker kicker--ch">
            <span className="kicker__n" aria-hidden="true">02</span>
            <span>Chapter two · where the audio goes</span>
          </p>
          <h2 id="features-title">Private by architecture,<br />not by promise.</h2>
          <p className="lede">
            In local mode your voice is turned into text on your own machine. That is not a policy you
            have to take on faith — it is simply where the code runs, and you can watch the network to
            confirm it.
          </p>
        </div>

        <div className="priv">
          <div>
            <div className="priv__cards">
              {CARDS.map(({ icon, title, body }) => (
                <article className="card" key={title}>
                  <span className="card__ico" aria-hidden="true"><Icon name={icon} /></span>
                  <h3>{title}</h3>
                  <p>{body}</p>
                </article>
              ))}
            </div>

            <p className="priv__quote" id="source">
              Don’t take our word for it: the source is{" "}
              <ExternalLink
                className="link"
                href={REPO_URL}
                data-analytics-event="github_outbound"
                data-analytics-placement="privacy"
              >
                public on GitHub
              </ExternalLink>
              , and you can point <code>Little Snitch</code> at the app and watch it stay quiet while
              you dictate.
            </p>
          </div>

          <div className="ledger">
            <p className="ledger__top">
              <span className="ledger__led" aria-hidden="true" /> Network activity — local mode
              <span className="ledger__top-r">traffic</span>
            </p>
            <ul>
              {LEDGER.map(({ happens, icon, label, note, tag }) => (
                <li key={label} className={happens ? undefined : "no"}>
                  <span className={happens ? "lg-i yes" : "lg-i no"} aria-hidden="true">
                    {happens && icon ? <Icon name={icon} size="sm" /> : "×"}
                  </span>
                  <span>
                    <b>{label}</b>
                    <br />
                    <em>{note}</em>
                  </span>
                  <span className={happens ? "lg-tag lg-tag--yes" : "lg-tag"}>{tag}</span>
                </li>
              ))}
            </ul>
            <p className="ledger__foot">
              That is the complete list for local mode. Add a cloud model with your own API key and one
              more destination appears — the provider you chose, reached directly from your Mac.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
