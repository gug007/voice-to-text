import { DictationDemo } from "@/components/dictation-demo";

export function Demo() {
  return (
    <section className="section demo reveal" id="demo" aria-labelledby="demo-title">
      <div className="container">
        <p className="section__eyebrow">See it work</p>
        <h2 id="demo-title" className="section__title">Speech to text in any Mac app.</h2>
        <p className="section__deck">
          Press the hotkey. Speak a full sentence. Press again. Your voice is transcribed and typed at the
          cursor — in an email, a Slack thread, a Notion page, a Google Doc, ChatGPT, or a code editor —
          without ever leaving your Mac.
        </p>
        <DictationDemo />
      </div>
    </section>
  );
}
