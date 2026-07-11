import Link from "next/link";

import { DictationDemo } from "@/components/dictation-demo";
import { Icon } from "@/components/ui/icon";
import { DMG_URL, GUIDE_PATH } from "@/lib/constants";

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
        <div className="demo__actions">
          <a
            className="btn btn--primary"
            href={DMG_URL}
            data-analytics-event="download_click"
            data-analytics-placement="primary_demo"
          >
            <Icon name="download" />
            <span>Try it free on your Mac</span>
          </a>
          <Link className="btn btn--secondary" href={GUIDE_PATH}>
            <span>Read the 5-minute setup guide</span>
            <Icon name="arrow-right" />
          </Link>
        </div>
      </div>
    </section>
  );
}
