import Image from "next/image";
import Link from "next/link";

import { DMG_URL, GUIDE_PATH, RELEASES_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";

export function Download() {
  return (
    <section className="section download" id="download" aria-labelledby="download-title">
      <div className="container download__inner">
        <div className="download__glow" aria-hidden="true" />
        <div className="download__plate">
          <Image className="download__icon" src="/app-icon.png" width={56} height={56} alt="VoiceToText app icon" />
          <h2 id="download-title" className="section__title">
            Install it in the time it takes to say so.
          </h2>
          <p className="section__deck">
            Download VoiceToText for Mac free: open the DMG, drag it to Applications, grant two permissions,
            press <HotkeyCombo />. Signed, notarized, and served from GitHub Releases.
          </p>
          <div className="download__ctas">
            <a
              className="btn btn--primary btn--lg"
              href={DMG_URL}
              data-analytics-event="download_click"
              data-analytics-placement="home_footer"
            >
              <Icon name="download" />
              <span>Download for Mac</span>
            </a>
            <ExternalLink className="btn btn--secondary btn--lg" href={RELEASES_URL}>
              <Icon name="github" />
              <span>All releases on GitHub</span>
            </ExternalLink>
          </div>
          <p className="download__note t-caption">
            macOS 15.0 or later · Apple Silicon (M1 or newer) · Updates install in place.
          </p>
          <p className="download__note t-caption">
            Need it step by step? <Link className="link" href={GUIDE_PATH}>Read the Mac setup guide</Link>.
          </p>
        </div>
      </div>
    </section>
  );
}
