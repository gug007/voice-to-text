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
    title: "Transcription runs on your Mac",
    body: "FluidAudio and WhisperKit run Parakeet and Whisper directly on Apple Silicon, so your audio never leaves the Mac. Parakeet, the default, works with the network off after its one-time download. Whisper models need a connection each time they load, because the current version checks with Hugging Face first.",
  },
  {
    icon: "cloud",
    title: "Cloud is opt-in, with your own key",
    body: "Pick a cloud model and the audio goes straight from your Mac to OpenAI or ElevenLabs on your key. AI actions and recording summaries send transcript text to OpenAI the same way. VoiceToText has no servers of its own to sit in that path.",
  },
];

type Permission = { name: string; when: string };

// Settings/PermissionCopy.swift, Audio/Permissions.swift, Meetings/MeetingController.swift
const PERMISSIONS: Permission[] = [
  { name: "Microphone", when: "so it can hear you" },
  { name: "Accessibility", when: "for the global shortcut, Esc and pasting — dictation won’t start without it" },
  { name: "Input Monitoring", when: "only if your shortcut is Right Control on its own" },
  { name: "Screen Recording", when: "only for Conversations — it carries the call audio; the screen is never recorded" },
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
    note: "once per model, from Hugging Face",
    tag: "once",
  },
  {
    happens: true,
    icon: "box",
    label: "Whisper model load",
    note: "a Hugging Face check each time one loads, after every launch; Parakeet loads offline",
    tag: "on load",
  },
  {
    happens: true,
    icon: "cloud",
    label: "Update check",
    note: "GitHub Releases, at launch and every 24 h; you confirm installs",
    tag: "daily",
  },
  {
    happens: false,
    label: "Your audio",
    note: "transcribed on your Mac",
    tag: "never leaves",
  },
  {
    happens: false,
    label: "Your transcripts",
    note: "saved in History on your Mac; saving dictations can be switched off",
    tag: "stays local",
  },
  {
    happens: false,
    label: "App telemetry",
    note: "no analytics, no crash-reporting SDK",
    tag: "none",
  },
  {
    happens: false,
    label: "Accounts & sync",
    note: "no sign-in exists",
    tag: "none",
  },
];

/** What adds a destination, and only when you turn it on. */
const OPT_IN: LedgerRow[] = [
  {
    happens: true,
    icon: "cloud",
    label: "Cloud transcription",
    note: "audio to OpenAI or ElevenLabs",
    tag: "your key",
  },
  {
    happens: true,
    icon: "sparkle",
    label: "AI actions & summaries",
    note: "transcript text, not audio, to OpenAI",
    tag: "your key",
  },
  {
    happens: true,
    icon: "lock",
    label: "Adding an API key",
    note: "one request to verify it with that provider",
    tag: "once",
  },
];

/** `optIn` rows are drawn in the accent, not the "happens" green: they are
    connections you switch on, not ones the app makes by itself. */
function LedgerRows({ rows, optIn = false }: { rows: LedgerRow[]; optIn?: boolean }) {
  const yes = optIn ? "opt" : "yes";
  return (
    <ul>
      {rows.map(({ happens, icon, label, note, tag }) => (
        <li key={label} className={happens ? undefined : "no"}>
          <span className={happens ? `lg-i ${yes}` : "lg-i no"} aria-hidden="true">
            {happens && icon ? <Icon name={icon} size="sm" /> : "×"}
          </span>
          <span>
            <b>{label}</b>{" "}
            <br />
            <em>{note}</em>
          </span>
          <span className={happens ? `lg-tag lg-tag--${yes}` : "lg-tag"}>{tag}</span>
        </li>
      ))}
    </ul>
  );
}

export function Features() {
  return (
    <section className="section" id="features" aria-labelledby="features-title">
      <div className="wrap">
        <div className="sec-head">
          <p className="kicker kicker--ch">
            <span className="kicker__n" aria-hidden="true">03</span>
            <span>Chapter three · where the audio goes</span>
          </p>
          <h2 id="features-title">Private by architecture,{" "}<br />not by promise.</h2>
          <p className="lede">
            In local mode your voice is turned into text on your own Mac. That is not a policy you have to take
            on faith — it is simply where the code runs, and you can watch the network to confirm it.
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
              <article className="card">
                <span className="card__ico" aria-hidden="true"><Icon name="lock" /></span>
                <h3>Permissions, and what each is for</h3>
                <ul className="perms">
                  {PERMISSIONS.map(({ name, when }) => (
                    <li key={name}>
                      <b>{name}</b> <span>{when}</span>
                    </li>
                  ))}
                </ul>
              </article>
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
              you dictate with Parakeet, the default model.
            </p>
          </div>

          <div className="ledger">
            <p className="ledger__top">
              <span className="ledger__led" aria-hidden="true" /> Network activity — local mode
              <span className="ledger__top-r">traffic</span>
            </p>
            <LedgerRows rows={LEDGER} />
            <p className="ledger__sub">Only if you opt in</p>
            <LedgerRows rows={OPT_IN} optIn />
            <p className="ledger__foot">
              With local models and no API keys, the first list is complete. Every opt-in connection goes
              straight from your Mac to the provider you chose, on your own key.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
