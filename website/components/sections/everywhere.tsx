import type { CSSProperties, ReactNode } from "react";

import { ExternalLink } from "@/components/ui/external-link";
import { Glyph, type GlyphName } from "@/components/ui/glyph";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { BUILT_IN_ACTIONS, MODEL_CATALOG } from "@/lib/app-facts";
import { INTEGRATION_URL } from "@/lib/constants";
import { countWord } from "@/lib/seo";

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

// 23 apps plus the closing "anywhere ⌘V pastes" tile: 24 fills whole rows of
// 6 and 4, the grid's two column counts (phones flow the tiles as pills).
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
  { name: "Linear", mark: "Li", hue: 218 },
  { name: "Safari", mark: "Sf", hue: 218 },
  { name: "Chrome", mark: "Cr", hue: 238 },
  { name: "ChatGPT", mark: "GP", hue: 178 },
  { name: "Claude.ai", mark: "Cl", hue: 198 },
  { name: "Cursor", mark: "Cu", hue: 258 },
  { name: "VS Code", mark: "VS", hue: 218 },
  { name: "Xcode", mark: "Xc", hue: 198 },
  { name: "Terminal", mark: ">_", hue: 238 },
];

type BuiltIn = {
  glyph: GlyphName;
  title: string;
  body: ReactNode;
};

const BUILT_INS: BuiltIn[] = [
  {
    glyph: "search",
    title: "History, searchable",
    body: "Your latest 200 dictations and recordings stay on your Mac. Search transcripts, summaries, action items and speaker names.",
  },
  {
    glyph: "versions",
    title: "Regenerate, keep both",
    body: `Re-run any saved recording with another of the ${MODEL_CATALOG.length} models. Each version stays side by side.`,
  },
  {
    glyph: "sparkles",
    title: "AI actions",
    body: `${BUILT_IN_ACTIONS.slice(0, 3).join(", ")} and ${countWord(BUILT_IN_ACTIONS.length - 3).toLowerCase()} more, plus your own — ⌘1–⌘9 in the review panel. Off until you switch them on in Settings → Actions and add an OpenAI key.`,
  },
  {
    glyph: "terminal",
    title: "Automation",
    body: (
      <>
        <code>open -g voicetotext://toggle</code> starts or stops dictation from Raycast, Shortcuts, Stream Deck
        or a script.{" "}
        <ExternalLink
          className="link"
          href={INTEGRATION_URL}
          data-analytics-event="github_outbound"
          data-analytics-placement="everywhere_automation"
        >
          URL commands
        </ExternalLink>
      </>
    ),
  },
  {
    glyph: "menubar",
    title: "Menu bar and Dock",
    body: "Start dictation or a recording from the menu bar. Hide the Dock icon to run menu-bar-only; it opens at login unless you turn that off.",
  },
  {
    glyph: "headphones",
    title: "Survives mic switches",
    body: "If AirPods or another mic reconnects mid-dictation, capture restarts on its own. If it can’t, what you said is still transcribed.",
  },
  {
    glyph: "update",
    title: "One-click updates",
    body: "Checks GitHub Releases at launch and once a day. You confirm each install, or skip that version.",
  },
  {
    glyph: "contrast",
    title: "Light, Dark or System",
    body: "Follow macOS or pick one. The recording HUD follows too.",
  },
];

export function Everywhere() {
  return (
    <section className="section" id="everywhere" aria-labelledby="everywhere-title">
      <div className="wrap">
        <div className="sec-head">
          <p className="kicker kicker--ch">
            <span className="kicker__n" aria-hidden="true">05</span>
            <span>Chapter five · no integrations required</span>
          </p>
          <h2 id="everywhere-title">If you can paste there,{" "}<br />you can dictate there.</h2>
          <p className="lede">
            There is no plugin list and no per-app setup. VoiceToText pastes the text at your cursor with a standard
            ⌘V, then puts your clipboard back the way it was. These are just places people use it.
          </p>
        </div>

        <ul className="apps apps--tiles" role="list">
          {APPS.map(({ name, mark, hue }) => (
            <li className="app" key={name}>
              <span className="app__i" style={{ "--h": hue } as HueVars} aria-hidden="true">{mark}</span>
              {name}
            </li>
          ))}
          <li className="app app--any">
            <span className="app__i" aria-hidden="true">⌘V</span>
            Any text field
          </li>
        </ul>
        <p className="apps__foot">
          <b>Anywhere ⌘V pastes text.</b> Address bars, commit messages, chat composers, spreadsheet cells — press{" "}
          <HotkeyCombo /> and the words land at your cursor. A field that blocks pasting won’t take them.
        </p>

        <div className="builtin">
          <h3 className="builtin__title">Built in, nothing to install</h3>
          <ul className="builtin__grid" role="list">
            {BUILT_INS.map(({ glyph, title, body }) => (
              <li className="builtin__item" key={title}>
                <span className="builtin__ico" aria-hidden="true"><Glyph name={glyph} /></span>
                <h4>{title}</h4>
                <p>{body}</p>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}
