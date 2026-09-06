import Link from "next/link";

import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";
import { DMG_URL, GUIDE_PATH } from "@/lib/constants";

export function Demo() {
  return (
    <section className="section demo" id="demo" aria-labelledby="demo-title">
      <div className="container">
        <div className="section__head section__head--center">
          <h2 id="demo-title" className="section__title">The real app, dictating a prompt in 20 seconds.</h2>
          <p className="section__deck">
            A screen recording of VoiceToText typing into a coding workspace. No copy and paste, no
            window switching, nothing staged.
          </p>
        </div>
        <figure className="product-demo">
          <div className="product-demo__window">
            <div className="product-demo__chrome" aria-hidden="true">
              <span className="product-demo__chrome-title">Screen recording, no audio</span>
            </div>
            <video
              className="product-demo__video"
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
          </div>
          <figcaption className="product-demo__caption">
            <span>Press <HotkeyCombo />, speak, press again. The transcript lands at the cursor.</span>
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
            <span>Try it on your Mac</span>
          </a>
          <Link className="btn btn--secondary" href={GUIDE_PATH}>
            <span>Read the setup guide</span>
          </Link>
        </div>
      </div>
    </section>
  );
}
