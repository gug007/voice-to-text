import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { TrafficLights } from "@/components/ui/traffic-lights";

const ACTIONS = [
  { name: "Clean transcript", hint: "⌘1" },
  { name: "To English", hint: "⌘2" },
  { name: "Improve prompt", hint: "⌘3" },
  { name: "Fix grammar", hint: "⌘4" },
  { name: "Summarize", hint: "⌘5" },
  { name: "Essentials only", hint: "⌘6" },
] as const;

const SAMPLE =
  "Let's ship the build before lunch, and circle back on the API rename tomorrow.";

export function Review() {
  return (
    <section className="section review reveal" id="review" aria-labelledby="review-title">
      <div className="container">
        <p className="section__eyebrow">Own the output</p>
        <h2 id="review-title" className="section__title">
          Review, refine — then it types.
        </h2>
        <p className="section__deck">
          By default, your transcript lands in a small floating panel first. Edit it, run a one-click AI
          action on it, keep dictating at the caret, then paste. Nothing types until you confirm — or turn
          review off and text lands instantly.
        </p>
        <div className="ai__grid">
          <div className="ai__body">
            <p className="ai__para">
              AI Actions transform the transcript before it&rsquo;s pasted: clean out filler words, translate to
              English, restructure a rambling request into a crisp AI prompt, fix grammar, or boil it down
              to the essentials. Six actions are built in — flip on the ones you want in{" "}
              <em>Settings → Actions</em> — every one is editable, and you can write your own. They run with
              your own OpenAI key, and each transform can be undone.
            </p>
            <ul className="ai__apps" role="list" aria-label="Built-in AI actions">
              {ACTIONS.map(({ name, hint }, i) => (
                <li key={name} className="ai__app">
                  {name} <span className="review-chip__hint" aria-hidden="true">{hint}</span>
                  <span className="sr-only">{`, shortcut Command ${i + 1}`}</span>
                </li>
              ))}
            </ul>
          </div>
          <figure className="ai__transcript" aria-label="The review panel shown after a dictation">
            <div className="ai__transcript-chrome" aria-hidden="true">
              <TrafficLights />
              <span className="ai__transcript-title">Review — VoiceToText</span>
            </div>
            <p className="review-panel__text">{SAMPLE}</p>
            <div className="review-panel__keys" aria-hidden="true">
              <span className="review-panel__key">Cancel <kbd className="keycap keycap--inline">esc</kbd></span>
              <span className="review-panel__key">Resume <kbd className="keycap keycap--inline">⌘R</kbd></span>
              <span className="review-panel__key review-panel__key--primary">
                Paste <HotkeyCombo />
              </span>
            </div>
            <figcaption className="ai__transcript-caption">
              <strong>Edit, transform, or re-dictate at the caret.</strong> Every take you keep is saved to
              History — cancel, and it&rsquo;s wiped from disk.
            </figcaption>
          </figure>
        </div>
      </div>
    </section>
  );
}
