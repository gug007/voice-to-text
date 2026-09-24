"use client";

import type { KeyboardEvent } from "react";
import { useId, useRef, useState } from "react";

import { Glyph, type GlyphName } from "@/components/ui/glyph";
import s from "@/components/sections/conversations.module.css";

/*
 * The Conversations pane, drawn after the app's own layout
 * (Settings/MeetingSettingsView.swift, RecordingRow.swift and
 * RecordingInsightsView.swift): the session card, then one saved recording
 * with its Transcript | Summary | Action Items | custom-result tab bar.
 *
 * The window chrome, sidebar and session card are decorative. The recording
 * itself is a real, keyboard-operable tab set, so everything it shows is
 * readable text. The meeting is invented sample content.
 */

type TabId = "transcript" | "summary" | "actions" | "minutes";

type Tab = { id: TabId; label: string; glyph: GlyphName };

const TABS: Tab[] = [
  { id: "transcript", label: "Transcript", glyph: "bubble" },
  { id: "summary", label: "Summary", glyph: "summary" },
  { id: "actions", label: "Action Items", glyph: "checklist" },
  // A custom result: the model names the tab, in three words or fewer.
  { id: "minutes", label: "Minutes", glyph: "sparkles" },
];

const TRANSCRIPT: ReadonlyArray<{ who: string; said: string }> = [
  { who: "Maya", said: "Beta feedback is in. Most of it is about onboarding, not the editor." },
  { who: "Dev", said: "Then the empty state goes first. I can have a draft by Thursday." },
  { who: "Maya", said: "Good. Sam, can you get the churn numbers before the review?" },
  { who: "Sam", said: "Yes, I’ll send them Wednesday." },
  { who: "Maya", said: "And I’ll share the beta notes with design." },
];

type ActionItem = { task: string; owner: string; due?: string };

// Owner and due appear only where the transcript says them — the third item
// has no date because nobody gave one.
const ACTION_ITEMS: ActionItem[] = [
  { task: "Draft the new empty state", owner: "Dev", due: "by Thursday" },
  { task: "Send the churn numbers", owner: "Sam", due: "Wednesday" },
  { task: "Share the beta notes with design", owner: "Maya" },
];

const SIDEBAR: ReadonlyArray<{ group: string; items: string[] }> = [
  { group: "Dictate", items: ["General", "Conversations", "History"] },
  { group: "Configure", items: ["Shortcut", "Models", "Actions", "Cloud", "Updates"] },
];

function itemsCaption(done: boolean[]): string {
  const count = done.filter(Boolean).length;
  return `${ACTION_ITEMS.length} action items · ${count} done`;
}

export function ConversationMockup() {
  const baseId = useId();
  const [selected, setSelected] = useState<TabId>("transcript");
  const [done, setDone] = useState<boolean[]>(() => ACTION_ITEMS.map((_, i) => i === 0));
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);

  const tabId = (id: TabId) => `${baseId}-tab-${id}`;
  const panelId = (id: TabId) => `${baseId}-panel-${id}`;

  // WAI-ARIA tabs with automatic activation: arrows move and select,
  // Home/End jump to the ends.
  function onTabKeyDown(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    let next = index;
    if (event.key === "ArrowRight") next = (index + 1) % TABS.length;
    else if (event.key === "ArrowLeft") next = (index - 1 + TABS.length) % TABS.length;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = TABS.length - 1;
    else return;
    event.preventDefault();
    setSelected(TABS[next].id);
    tabRefs.current[next]?.focus();
  }

  return (
    <figure className={s.figure}>
      <div className={s.win}>
        <div className={s.bar} aria-hidden="true">
          <span className={`${s.dot} ${s.dotR}`} />
          <span className={`${s.dot} ${s.dotY}`} />
          <span className={`${s.dot} ${s.dotG}`} />
          <span className={s.barTitle}>VoiceToText</span>
          <span className={s.barPad} />
        </div>

        <div className={s.body}>
          <div className={s.side} aria-hidden="true">
            {SIDEBAR.map(({ group, items }) => (
              <div key={group} className={s.sideGroup}>
                <span className={s.sideHead}>{group}</span>
                {items.map((item) => (
                  <span key={item} className={item === "Conversations" ? `${s.sideItem} ${s.sideItemOn}` : s.sideItem}>
                    {item}
                  </span>
                ))}
              </div>
            ))}
          </div>

          <div className={s.pane}>
            <div aria-hidden="true">
              <p className={s.paneTitle}>Conversations</p>
              <p className={s.paneSub}>Your mic plus everything you hear, transcribed when you stop.</p>

              <div className={s.session}>
                <div className={s.sessionState}>
                  <span className={s.readyDot} />
                  <span>Ready</span>
                  <span className={s.sessionClock}>0:00</span>
                </div>
                <div className={s.sessionBtns}>
                  <span className={`${s.capsule} ${s.capsulePrimary}`}>
                    <Glyph name="record" className={s.recGlyph} />
                    Start Recording
                  </span>
                  <span className={s.capsule}>
                    <Glyph name="upload" />
                    Upload File…
                  </span>
                </div>
              </div>
            </div>

            <article className={s.row} aria-label="Example conversation: product sync">
              <div className={s.rowHead}>
                <span className={s.play} aria-hidden="true">
                  <Glyph name="play" />
                </span>
                <span className={s.rowMeta}>
                  <span className={s.rowDate}>Today at 10:30 AM</span>
                  <span className={s.rowLine}>
                    <span className={s.typeBadge}>Conversation</span>
                    <span>12:48</span>
                    <span className={s.rowSep} aria-hidden="true">·</span>
                    <span className={s.rowModel}>GPT-4o Transcribe Diarize</span>
                  </span>
                </span>
                <span className={s.rowTools} aria-hidden="true">
                  <Glyph name="person" />
                  <Glyph name="sparkles" />
                  <Glyph name="star" />
                </span>
              </div>

              <div className={s.tabs} role="tablist" aria-label="Views of this recording">
                {TABS.map((tab, i) => {
                  const isOn = tab.id === selected;
                  return (
                    <button
                      key={tab.id}
                      ref={(el) => {
                        tabRefs.current[i] = el;
                      }}
                      type="button"
                      role="tab"
                      id={tabId(tab.id)}
                      aria-selected={isOn}
                      aria-controls={panelId(tab.id)}
                      tabIndex={isOn ? 0 : -1}
                      className={s.tab}
                      onClick={() => setSelected(tab.id)}
                      onKeyDown={(event) => onTabKeyDown(event, i)}
                    >
                      <Glyph name={tab.glyph} className={s.tabGlyph} />
                      {tab.label}
                      {tab.id === "actions" ? (
                        <span className={s.tabCount}>
                          <span className="sr-only">, </span>
                          {ACTION_ITEMS.length}
                        </span>
                      ) : null}
                    </button>
                  );
                })}
              </div>

              <div className={s.panels}>
                <div
                  className={s.panel}
                  role="tabpanel"
                  id={panelId("transcript")}
                  aria-labelledby={tabId("transcript")}
                  data-hidden={selected !== "transcript" || undefined}
                  inert={selected !== "transcript"}
                  tabIndex={0}
                >
                  <ul className={s.turns}>
                    {TRANSCRIPT.map(({ who, said }, i) => (
                      <li key={i}>
                        <b>{who}:</b> {said}
                      </li>
                    ))}
                  </ul>
                </div>

                <div
                  className={s.panel}
                  role="tabpanel"
                  id={panelId("summary")}
                  aria-labelledby={tabId("summary")}
                  data-hidden={selected !== "summary" || undefined}
                  inert={selected !== "summary"}
                  tabIndex={0}
                >
                  <p className={s.panelCaption}>Summary · just now</p>
                  <div className={s.summary}>
                    <p>The team went through the beta feedback and agreed to fix onboarding before more editor work.</p>
                    <p className={s.summaryHead}>Onboarding</p>
                    <ul>
                      <li>Most beta feedback is about the first-run experience.</li>
                      <li>Dev is drafting a new empty state first.</li>
                    </ul>
                    <p className={s.summaryHead}>Before the review</p>
                    <ul>
                      <li>Sam sends the churn numbers; Maya shares the beta notes with design.</li>
                    </ul>
                  </div>
                </div>

                <div
                  className={s.panel}
                  role="tabpanel"
                  id={panelId("actions")}
                  aria-labelledby={tabId("actions")}
                  data-hidden={selected !== "actions" || undefined}
                  inert={selected !== "actions"}
                >
                  <p className={s.panelCaption} aria-live="polite">
                    {itemsCaption(done)}
                  </p>
                  <ul className={s.items}>
                    {ACTION_ITEMS.map(({ task, owner, due }, i) => (
                      <li key={task}>
                        <label className={s.item}>
                          <input
                            type="checkbox"
                            className={s.check}
                            checked={done[i]}
                            onChange={() => setDone((prev) => prev.map((value, j) => (j === i ? !value : value)))}
                          />
                          <span className={s.itemBody}>
                            <span className={s.itemTask}>{task}</span>
                            <span className={s.itemChips}>
                              <span className={s.itemChip}>
                                <Glyph name="person" />
                                <span className="sr-only">Owner: </span>
                                {owner}
                              </span>
                              {due ? (
                                <span className={s.itemChip}>
                                  <Glyph name="clock" />
                                  <span className="sr-only">Due: </span>
                                  {due}
                                </span>
                              ) : null}
                            </span>
                          </span>
                        </label>
                      </li>
                    ))}
                  </ul>
                </div>

                <div
                  className={s.panel}
                  role="tabpanel"
                  id={panelId("minutes")}
                  aria-labelledby={tabId("minutes")}
                  data-hidden={selected !== "minutes" || undefined}
                  inert={selected !== "minutes"}
                  tabIndex={0}
                >
                  <p className={s.panelCaption}>“Rewrite this as meeting minutes”</p>
                  <div className={s.summary}>
                    <p className={s.summaryHead}>Product sync</p>
                    <p>Attendees: Maya, Dev, Sam</p>
                    <p>Decision: onboarding comes before further editor work.</p>
                    <p className={s.summaryHead}>Actions</p>
                    <ul>
                      <li>Dev — empty-state draft, by Thursday</li>
                      <li>Sam — churn numbers, Wednesday</li>
                      <li>Maya — beta notes to design</li>
                    </ul>
                  </div>
                </div>
              </div>
            </article>
          </div>
        </div>
      </div>
      <figcaption className={s.caption}>
        An example recording in the Conversations pane. Switch tabs to see the summary, the action items and a custom
        result.
      </figcaption>
    </figure>
  );
}
