import type { CSSProperties } from "react";

import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon, type IconName } from "@/components/ui/icon";

/** Each app tile colours its monogram from a hue set inline. Hues stay on the
    duotone axis — teal 178 to violet 258 — so the grid reads as one palette. */
type HueVars = CSSProperties & Record<"--h", number>;

type App = {
  name: string;
  /** Two-character monogram shown in the tile. */
  mark: string;
  /** 178-258: teal-to-violet band of the duotone palette. */
  hue: number;
};

const APPS: App[] = [
  { name: "Slack", mark: "Sl", hue: 258 },
  { name: "Mail", mark: "Ma", hue: 218 },
  { name: "Notes", mark: "No", hue: 198 },
  { name: "Notion", mark: "Nt", hue: 238 },
  { name: "Obsidian", mark: "Ob", hue: 258 },
  { name: "Bear", mark: "Be", hue: 178 },
  { name: "Pages", mark: "Pa", hue: 198 },
  { name: "Google Docs", mark: "GD", hue: 238 },
  { name: "Microsoft Word", mark: "W", hue: 258 },
  { name: "Messages", mark: "Ms", hue: 178 },
  { name: "Gmail", mark: "Gm", hue: 198 },
  { name: "Outlook", mark: "Ou", hue: 238 },
  { name: "WhatsApp", mark: "Wa", hue: 178 },
  { name: "Discord", mark: "Dc", hue: 258 },
  { name: "Safari", mark: "Sf", hue: 218 },
  { name: "Chrome", mark: "Cr", hue: 238 },
  { name: "ChatGPT", mark: "GP", hue: 178 },
  { name: "Claude.ai", mark: "Cl", hue: 198 },
  { name: "Cursor", mark: "Cu", hue: 258 },
  { name: "Terminal", mark: ">_", hue: 218 },
];

type Extra = {
  icon: IconName;
  title: string;
  body: string;
};

const EXTRAS: Extra[] = [
  {
    icon: "mic",
    title: "Meeting recording",
    body: "Captures your microphone and system audio together and transcribes locally by default. No bot joins the call, and nobody gets an invite from a vendor.",
  },
  {
    icon: "box",
    title: "Local history",
    body: "Past recordings and transcripts are kept on your Mac, so you can go back for the note you forgot to paste. Nothing is uploaded to make that work.",
  },
  {
    icon: "sparkle",
    title: "Optional AI clean-up",
    body: "Tidy up or summarise a transcript after the fact. It uses your own OpenAI key, and like every cloud feature it stays off until you switch it on.",
  },
];

export function Everywhere() {
  return (
    <section className="section" id="everywhere" aria-labelledby="everywhere-title">
      <div className="wrap">
        <div className="sec-head">
          <p className="kicker kicker--ch">
            <span className="kicker__n" aria-hidden="true">04</span>
            <span>Chapter four · no integrations required</span>
          </p>
          <h2 id="everywhere-title">If it has a text field,<br />it already works.</h2>
          <p className="lede">
            There is no plugin list and no per-app configuration, because the text arrives the same way
            it would if you had typed it. These are just places people use it.
          </p>
        </div>

        <ul className="apps" role="list">
          {APPS.map(({ name, mark, hue }) => (
            <li className="app" key={name}>
              <span className="app__i" style={{ "--h": hue } as HueVars} aria-hidden="true">{mark}</span>
              {name}
            </li>
          ))}
        </ul>
        <p className="apps__foot">
          <b>Any Mac app with a text field.</b> Address bars, commit messages, chat composers,
          spreadsheet cells — press <HotkeyCombo /> and the words land at your cursor. No per-app setup.
        </p>

        <div className="extras">
          {EXTRAS.map(({ icon, title, body }) => (
            <article className="card" key={title}>
              <span className="card__ico" aria-hidden="true"><Icon name={icon} /></span>
              <h3>{title}</h3>
              <p>{body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
