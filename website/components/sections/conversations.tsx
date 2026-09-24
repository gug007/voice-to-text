import Link from "next/link";
import type { ReactNode } from "react";

import { ConversationMockup } from "@/components/ui/conversation-mockup";
import { MEETING_PATH } from "@/lib/seo";
import { MODEL_CATALOG } from "@/lib/app-facts";

import s from "./conversations.module.css";

type Step = {
  title: string;
  body: ReactNode;
  note?: string;
};

const STEPS: Step[] = [
  {
    title: "Start it however you like.",
    body: (
      <>
        Press <em>Start Recording</em> in Conversations, use the menu bar, or set an optional Conversation
        shortcut that works from any app. VoiceToText records your microphone and the call audio your Mac plays,
        so it works with Zoom, Google Meet, Teams, FaceTime, Webex or Discord. No bot joins the call.
      </>
    ),
    note: "Needs Microphone and Screen Recording permission. Screen Recording is how macOS shares call audio — the screen itself is never recorded.",
  },
  {
    title: "Or drop in a file.",
    body: (
      <>
        Choose <em>Upload File…</em> or drag one audio or video file onto the pane — MP3, M4A, WAV, AIFF, MP4, MOV
        and the other formats macOS can read.
      </>
    ),
  },
  {
    title: "Transcribed when you stop.",
    body: (
      <>
        On your Mac by default, with its own model setting, so calls can use a different model from dictation.
        Calls over 12 minutes are transcribed in parts of about 10 minutes, each cut at the quietest nearby
        moment. To see who said what, pick GPT-4o
        Transcribe Diarize: it labels each speaker, and you rename “Speaker 1” to a real name.
      </>
    ),
    note: "Speaker labels come from that cloud model only: it runs on your OpenAI key, and the audio goes to OpenAI.",
  },
  {
    title: "Summary, action items, or your own prompt.",
    body: (
      <>
        One click writes a summary, or a checklist of action items with an owner and a due date where someone
        actually said them. Tick them off, or copy them as a Markdown checklist. Or type your own instruction,
        like “Rewrite this as meeting minutes” — each recording keeps up to three of those as tabs.
      </>
    ),
    note: "Optional, and off until you add an OpenAI key. The transcript text, not the audio, is sent to OpenAI on your key.",
  },
  {
    title: "Kept in History, on your Mac.",
    body: (
      <>
        Search across transcripts, summaries, action items and speaker names. Star favorites, play the audio
        back, or regenerate a transcript with any of the {MODEL_CATALOG.length} models and keep both versions.
        Audio streams to disk as you record, so if the Mac crashes the call is waiting in History at next
        launch, ready to transcribe.
      </>
    ),
  },
];

export function Conversations() {
  return (
    <section className="section section--band" id="conversations" aria-labelledby="conversations-title">
      <div className="wrap">
        <div className="sec-head">
          <p className="kicker kicker--ch">
            <span className="kicker__n" aria-hidden="true">02</span>
            <span>Chapter two · calls and recordings</span>
          </p>
          <h2 id="conversations-title">Record the call.{" "}<br />Keep what was decided.</h2>
          <p className="lede">
            Conversations records both sides of a call — your voice and everyone you hear — and turns it into a
            transcript when you stop. It runs on your Mac by default, and nothing joins the meeting.
          </p>
        </div>

        <div className={s.rig}>
          <div className={s.stage}>
            <ConversationMockup />
          </div>

          <div>
            <ol className={s.steps}>
              {STEPS.map(({ title, body, note }, i) => (
                <li key={title} className={s.step}>
                  <span className={s.stepN} aria-hidden="true">{String(i + 1).padStart(2, "0")}</span>
                  <div>
                    <h3>{title}</h3>
                    <p>{body}</p>
                    {note ? <p className={s.stepNote}>{note}</p> : null}
                  </div>
                </li>
              ))}
            </ol>

            <p className={s.more}>
              <Link className="link" href={MEETING_PATH}>
                How meeting recording works
              </Link>
              {" "}— permissions, file formats, speaker labels and exactly what is sent where.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
