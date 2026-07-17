"use client";

import Link from "next/link";
import { useState } from "react";

import { trackAnalyticsEvent } from "@/components/analytics-events";
import { Icon, type IconName } from "@/components/ui/icon";
import { DMG_URL, GUIDE_PATH } from "@/lib/constants";

type UseCase = {
  id: "writing" | "coding" | "meetings";
  label: string;
  icon: IconName;
  title: string;
  body: string;
  sample: string;
  apps: readonly string[];
  cta: string;
  href: string;
  internal?: boolean;
};

const USE_CASES: readonly UseCase[] = [
  {
    id: "writing",
    label: "Writing",
    icon: "apps",
    title: "Write emails, notes, and messages without breaking your flow.",
    body: "Put the cursor where you want the text, speak naturally, review the result, and press Return. VoiceToText handles punctuation and types into the app already in front of you.",
    sample: "Quick update — I finished the proposal and shared it with the team. I’ll send the final version before lunch tomorrow.",
    apps: ["Mail", "Notes", "Slack", "Notion"],
    cta: "Dictate your next message",
    href: DMG_URL,
  },
  {
    id: "coding",
    label: "AI & coding",
    icon: "agent",
    title: "Speak detailed prompts into ChatGPT, Cursor, or your terminal.",
    body: "Explain the context, constraints, and desired result out loud. Long technical requests become editable text at the cursor, ready to refine before you send them.",
    sample: "Refactor this function to stream tokens instead of buffering the full response, but keep the public type signature unchanged.",
    apps: ["ChatGPT", "Cursor", "Claude Code", "Terminal"],
    cta: "Set up voice prompts",
    href: GUIDE_PATH,
    internal: true,
  },
  {
    id: "meetings",
    label: "Meetings",
    icon: "mic",
    title: "Record both sides of a meeting and transcribe it on your Mac.",
    body: "Capture your microphone and system audio together while you keep working. The recording and transcript stay in local history, with cloud transcription available only when you choose it.",
    sample: "Decisions: ship the onboarding update on Tuesday, keep the current pricing, and review customer feedback after the release.",
    apps: ["Zoom", "Google Meet", "Teams", "FaceTime"],
    cta: "Explore meeting transcription",
    href: "/meeting-recording",
    internal: true,
  },
] as const;

export function UseCaseExplorer() {
  const [activeId, setActiveId] = useState<UseCase["id"]>("writing");
  const active = USE_CASES.find((item) => item.id === activeId) ?? USE_CASES[0];

  const selectUseCase = (id: UseCase["id"]) => {
    setActiveId(id);
    trackAnalyticsEvent("use_case_select", { placement: "home_use_cases", event_label: id });
  };

  const ctaContent = (
    <>
      <span>{active.cta}</span>
      <Icon name={active.internal ? "arrow-right" : "download"} />
    </>
  );

  return (
    <section className="section use-case-explorer reveal" id="use-cases" aria-labelledby="use-cases-title">
      <div className="container">
        <p className="section__eyebrow">Choose your workflow</p>
        <h2 id="use-cases-title" className="section__title">Where will voice to text save you time?</h2>
        <p className="section__deck">
          Dictate everyday writing, longer AI prompts, or entire meetings. Pick a workflow to see how
          VoiceToText fits the Mac apps you already use.
        </p>

        <div className="use-case-explorer__layout">
          <div className="use-case-explorer__choices" aria-label="Choose a VoiceToText workflow">
            {USE_CASES.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`use-case-choice${active.id === item.id ? " is-active" : ""}`}
                aria-pressed={active.id === item.id}
                onClick={() => selectUseCase(item.id)}
              >
                <span className="use-case-choice__icon" aria-hidden="true"><Icon name={item.icon} /></span>
                <span>
                  <strong>{item.label}</strong>
                  <small>{item.title}</small>
                </span>
                <Icon name="arrow-right" className="use-case-choice__arrow" />
              </button>
            ))}
          </div>

          <div className="use-case-panel" aria-live="polite">
            <p className="t-label">{active.label}</p>
            <h3>{active.title}</h3>
            <p className="use-case-panel__body">{active.body}</p>
            <blockquote className="use-case-panel__sample">
              <span className="use-case-panel__mic" aria-hidden="true"><Icon name="mic" /></span>
              <p>{active.sample}</p>
            </blockquote>
            <ul className="use-case-panel__apps" aria-label={`Example apps for ${active.label}`}>
              {active.apps.map((app) => <li key={app}>{app}</li>)}
            </ul>
            {active.internal ? (
              <Link
                className="btn btn--primary"
                href={active.href}
                data-analytics-event="use_case_cta"
                data-analytics-placement="home_use_cases"
                data-analytics-label={active.id}
              >
                {ctaContent}
              </Link>
            ) : (
              <a
                className="btn btn--primary"
                href={active.href}
                data-analytics-event="download_click"
                data-analytics-placement="home_use_cases"
              >
                {ctaContent}
              </a>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}
