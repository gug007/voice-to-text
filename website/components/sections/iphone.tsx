import Image from "next/image";

import { ExternalLink } from "@/components/ui/external-link";
import { Glyph, type GlyphName } from "@/components/ui/glyph";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { IPHONE_APP } from "@/lib/app-facts";
import { APP_STORE_URL } from "@/lib/constants";

import s from "./iphone.module.css";

type Point = { glyph: GlyphName; title: string; body: string };

const POINTS: Point[] = [
  {
    glyph: "record",
    title: "Transcribed on the phone",
    body: `Record a meeting, a lecture or a note to self, or import an audio or video file. ${IPHONE_APP.model} transcribes it on the iPhone in ${IPHONE_APP.languages}, offline after a one-time download of about ${IPHONE_APP.approxDownloadMB} MB. The audio stays on the phone.`,
  },
  {
    glyph: "search",
    title: "Search, play back, share",
    body: `Search every transcript, scrub the waveform, play at ${IPHONE_APP.playbackRange}, and share the text or the audio. Stop & Save keeps a recording to transcribe later.`,
  },
  {
    glyph: "summary",
    title: "Summary and action items",
    body: "Optional, with your own OpenAI key. Only the transcript text is sent, and only when you tap one.",
  },
  {
    glyph: "headphones",
    title: "A remote for your Mac",
    body: "Start or stop a recording on your Mac, read and play its conversations, or listen live while it records if the Mac allows it. They connect through your own Tailscale account, built into both apps.",
  },
];

type Shot = { src: string; alt: string; front?: boolean };

// App Store screenshots of the shipping build, 660 x 1434. Each <Image> gets the
// width it is drawn at on a wide screen (the CSS caps less the bezel), so Next
// emits a 1x/2x srcset instead of every breakpoint up to 3840.
const FRONT_WIDTH = 250;
const SIDE_WIDTH = 190;
const heightFor = (width: number) => Math.round((width * 1434) / 660);
const SHOTS: Shot[] = [
  {
    src: "/iphone/transcript.png",
    alt: "A recording on iPhone: a waveform player with playback speed, above Transcript, Summary and Action Items tabs.",
  },
  {
    src: "/iphone/recordings.png",
    alt: "Voice to Text on iPhone: recordings grouped by day, a Record button and transcript search.",
    front: true,
  },
  {
    src: "/iphone/mac-remote.png",
    alt: "The iPhone app showing a MacBook Pro that is recording, with Listen and Stop buttons.",
  },
];

export function IPhone() {
  return (
    <section className="section section--band" id="iphone" aria-labelledby="iphone-title">
      <div className="wrap">
        <div className={s.rig}>
          <div className={s.copy}>
            <div className="sec-head">
              <p className="kicker">Aside &middot; in your pocket</p>
              <h2 id="iphone-title">Now on iPhone.{" "}<br />Transcribed on the phone.</h2>
              <p className="lede">
                Voice to Text for iPhone records what&rsquo;s said in the room and transcribes it with the same
                Parakeet model the Mac app uses by default. It&rsquo;s free on the App Store, with no account,
                and it doubles as a remote for VoiceToText on your Mac.
              </p>
            </div>

            <ul className={s.points} role="list">
              {POINTS.map(({ glyph, title, body }) => (
                <li key={title} className={s.point}>
                  <span className={s.ico} aria-hidden="true"><Glyph name={glyph} /></span>
                  <div>
                    <h3>{title}</h3>
                    <p>{body}</p>
                  </div>
                </li>
              ))}
            </ul>

            <div className={s.cta}>
              <ExternalLink
                className="btn btn--primary btn--lg"
                href={APP_STORE_URL}
                data-analytics-event="app_store_outbound"
                data-analytics-placement="home_iphone"
              >
                <PhoneIcon />
                <span>Get it on the App Store</span>
              </ExternalLink>
              <p className={s.meta}>Free &middot; no account &middot; {IPHONE_APP.short}</p>
            </div>
            <p className={s.note}>
              It doesn&rsquo;t type into other iPhone apps. Dictating with <HotkeyCombo /> is on the Mac only.
            </p>
          </div>

          <div className={s.stage}>
            {SHOTS.map(({ src, alt, front }) => {
              const width = front ? FRONT_WIDTH : SIDE_WIDTH;
              return (
                <figure key={src} className={front ? `${s.phone} ${s.front}` : s.phone}>
                  <Image src={src} alt={alt} width={width} height={heightFor(width)} />
                </figure>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}

function PhoneIcon() {
  return (
    <svg
      className="icon"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="4" y="1.5" width="8" height="13" rx="2" />
      <path d="M7 12.2h2" />
    </svg>
  );
}
