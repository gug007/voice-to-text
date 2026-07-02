import { DMG_URL, INTEGRATION_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";
import { TrafficLights } from "@/components/ui/traffic-lights";

const APPS = [
  "Apple Notes",
  "Slack",
  "Messages",
  "Mail",
  "Gmail",
  "Notion",
  "Obsidian",
  "Pages",
  "Google Docs",
  "Safari",
  "Chrome",
  "ChatGPT",
  "Claude.ai",
  "Cursor",
  "Claude Code",
  "VS Code",
  "Warp",
  "Terminal",
] as const;

const SLACK_TRANSCRIPT = `▌ running late to standup — just
▌ finishing a customer call. start
▌ without me, I'll catch up after.`;

export function UseCases() {
  return (
    <section className="section ai reveal" id="use-cases" aria-labelledby="ai-title">
      <div className="container">
        <p className="section__eyebrow">Use cases</p>
        <h2 id="ai-title" className="section__title">
          Speak in every Mac app — from Notes and Slack to ChatGPT and Cursor.
        </h2>
        <p className="section__deck">
          Whatever app is in focus gets your words at the cursor. Writing an email, drafting a Slack reply,
          capturing a thought in Apple Notes, prompting ChatGPT, refactoring with Cursor — same hotkey, same
          speed.
        </p>
        <div className="ai__grid">
          <div className="ai__body">
            <p className="ai__para">
              A long Slack thread, a meeting note in Apple Notes, a draft in Notion, a Gmail reply, a search
              in your browser, a ChatGPT question, a Cursor refactor — same gesture every time. Press, speak,
              paste. Your voice never leaves the Mac in local mode. Building your own tool? Any app can
              trigger dictation through the{" "}
              <ExternalLink className="link" href={INTEGRATION_URL}>
                <code className="code-inline">voicetotext://</code> URL scheme
              </ExternalLink>
              .
            </p>
            <ul className="ai__apps" role="list" aria-label="Apps people use VoiceToText with">
              {APPS.map((name) => (
                <li key={name} className="ai__app">{name}</li>
              ))}
            </ul>
          </div>
          <figure className="ai__transcript" aria-label="Example of a voice-dictated Slack message">
            <div className="ai__transcript-chrome" aria-hidden="true">
              <TrafficLights />
              <span className="ai__transcript-title">Slack — #design</span>
              <span className="ai__transcript-hotkey" aria-hidden="true">
                <kbd className="keycap keycap--inline" aria-hidden="true">⌥</kbd>
                <kbd className="keycap keycap--inline" aria-hidden="true">Space</kbd>
              </span>
            </div>
            <pre className="ai__transcript-body"><code>{SLACK_TRANSCRIPT}</code></pre>
            <figcaption className="ai__transcript-caption">
              <strong>Spoken into Slack in one push.</strong> No window switch, no copy-paste.
            </figcaption>
          </figure>
        </div>
        <div className="ai__cta">
          <a className="btn btn--primary" href={DMG_URL}>
            <Icon name="download" />
            <span>Get it free — download for Mac</span>
          </a>
        </div>
      </div>
    </section>
  );
}
