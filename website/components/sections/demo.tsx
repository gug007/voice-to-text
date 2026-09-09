import type { CSSProperties } from "react";

const FRAME: CSSProperties = { maxWidth: "940px", margin: "0 auto" };

const VIDEO: CSSProperties = {
  display: "block",
  width: "100%",
  aspectRatio: "900 / 574",
  objectFit: "cover",
  background: "var(--surface-3, var(--surface-sunken))",
};

export function Demo() {
  return (
    <section className="section" id="demo" aria-labelledby="demo-title">
      <div className="wrap">
        <div className="sec-head">
          <p className="kicker">Interlude &middot; twenty seconds, unedited</p>
          <h2 id="demo-title">The real app, unedited.</h2>
          <p className="lede">
            Twenty seconds of VoiceToText dictating a prompt into a coding workspace on a Mac. No copy and
            paste, no window switching, nothing staged.
          </p>
        </div>

        <figure className="win" style={FRAME}>
          <div className="win__bar" aria-hidden="true">
            <span className="dot dot--r" />
            <span className="dot dot--y" />
            <span className="dot dot--g" />
            <span className="win__title">Screen recording, no audio</span>
            <span className="win__pad" />
          </div>
          <video
            style={VIDEO}
            controls
            muted
            loop
            playsInline
            preload="metadata"
            poster="/product-demo-poster.png"
            data-respect-reduced-motion
            data-analytics-event="demo_start"
            data-analytics-placement="home_demo"
            data-analytics-label="product_video"
            aria-label="Silent 20-second screen recording of VoiceToText dictating into a coding workspace"
          >
            <source src="/product-demo.mp4" type="video/mp4" />
            Your browser does not support embedded video. Use the setup guide below to see how VoiceToText works.
          </video>
        </figure>
      </div>
    </section>
  );
}
