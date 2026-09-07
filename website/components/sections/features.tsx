import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";

const APPS = [
  "Slack",
  "Mail",
  "Notes",
  "Notion",
  "ChatGPT",
  "Cursor",
  "Terminal",
  "Safari",
  "Google Docs",
  "Discord",
] as const;

export function Features() {
  return (
    <section className="section section--band features" id="features" aria-labelledby="features-title">
      <div className="container">
        <div className="section__head">
          <h2 id="features-title" className="section__title">Private by architecture, not by promise.</h2>
          <p className="section__deck">
            Local, offline transcription is the default. Cloud models and AI actions only turn on when you
            add your own provider key.
          </p>
        </div>
        <ul className="bento" role="list">
          <li className="bento__card bento__card--wide">
            <h3 className="bento__title">Your audio never leaves the Mac in local mode</h3>
            <p className="bento__text">
              WhisperKit and FluidAudio run Parakeet and Whisper on the Apple Neural Engine. No VoiceToText
              account, no first-party servers, no app telemetry.
            </p>
            <div className="pipeline" aria-hidden="true">
              <span className="pipeline__node"><Icon name="mic" />Your voice</span>
              <span className="pipeline__arrow">→</span>
              <span className="pipeline__node">Apple Neural Engine</span>
              <span className="pipeline__arrow">→</span>
              <span className="pipeline__node">Text at your cursor</span>
              <span className="pipeline__status"><span className="pipeline__dot" />On device</span>
            </div>
          </li>
          <li className="bento__card">
            <span className="feature-card__icon" aria-hidden="true"><Icon name="github" size="lg" /></span>
            <h3 className="bento__title">Auditable source</h3>
            <p className="bento__text">
              Every commit, issue, and release happens in the open on GitHub. Verify the permission handling
              yourself, or watch traffic with Little Snitch.
            </p>
          </li>
          <li className="bento__card">
            <span className="feature-card__icon" aria-hidden="true"><Icon name="bolt" size="lg" /></span>
            <h3 className="bento__title">Native Mac speed</h3>
            <p className="bento__text">
              Pure SwiftUI with no Electron overhead. Quick to launch and light in Activity Monitor.
            </p>
          </li>
          <li className="bento__card">
            <span className="feature-card__icon" aria-hidden="true"><Icon name="keyboard" size="lg" /></span>
            <h3 className="bento__title">Tap to talk, or hold</h3>
            <p className="bento__text">
              Press <HotkeyCombo /> to start and again to stop, or switch to hold-to-record. Rebind to any
              shortcut, even Right Control on its own.
            </p>
          </li>
          <li className="bento__card">
            <h3 className="bento__title">Works in every app that accepts text</h3>
            <ul className="chips" role="list" aria-label="Example apps">
              {APPS.map((app) => <li key={app}>{app}</li>)}
            </ul>
          </li>
        </ul>
      </div>
    </section>
  );
}
