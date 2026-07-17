import Link from "next/link";

import { Icon } from "@/components/ui/icon";
import { DMG_URL, GUIDE_PATH } from "@/lib/constants";

export function Demo() {
  return (
    <section className="section demo reveal" id="demo" aria-labelledby="demo-title">
      <div className="container">
        <p className="section__eyebrow">See it work</p>
        <h2 id="demo-title" className="section__title">From voice to a finished prompt in 20 seconds.</h2>
        <p className="section__deck">
          This is the real app dictating directly into a coding workspace — no copy and paste, no window
          switch, and no staged interface.
        </p>
        <figure className="product-demo">
          <div className="product-demo__frame">
            <video
              className="product-demo__video"
              controls
              autoPlay
              muted
              loop
              playsInline
              preload="metadata"
              poster="/product-demo-poster.png"
              data-respect-reduced-motion
              data-analytics-event="demo_video_interaction"
              data-analytics-placement="home_demo"
              aria-label="Silent 20-second screen recording of VoiceToText dictating into a coding workspace"
            >
              <source src="/product-demo.mp4" type="video/mp4" />
              Your browser does not support embedded video. Use the setup guide below to see how VoiceToText works.
            </video>
          </div>
          <figcaption className="product-demo__caption">
            <span><strong>Real screen recording</strong> · 20 seconds · no audio</span>
            <span>Press <kbd className="keycap keycap--inline">⌥</kbd><kbd className="keycap keycap--inline">Space</kbd>, speak, press again.</span>
          </figcaption>
        </figure>
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
