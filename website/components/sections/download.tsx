import Image from "next/image";
import Link from "next/link";
import type { CSSProperties } from "react";

import { DMG_URL, GUIDE_PATH, RELEASES_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";

const APP_ICON: CSSProperties = { borderRadius: "12px", marginBottom: "16px" };

export function Download() {
  return (
    <section className="section" id="download" aria-labelledby="download-title">
      <div className="wrap">
        <div className="get">
          <div className="get__in">
            <div>
              <Image style={APP_ICON} src="/app-icon.png" width={48} height={48} alt="VoiceToText app icon" />
              <p className="kicker kicker--ch">
                <span className="kicker__n" aria-hidden="true">06</span>
                <span>Last beat &middot; the install</span>
              </p>
              <h2 id="download-title">Install it in the time it takes to say so.</h2>
              <p className="lede">
                Free, open source, and quiet by default. Signed, notarized, and served from GitHub
                Releases — if it isn&rsquo;t for you, drag it to the Trash and nothing of yours went
                anywhere.
              </p>
              <div className="get__cta">
                <a
                  className="btn btn--primary btn--lg"
                  href={DMG_URL}
                  data-analytics-event="download_click"
                  data-analytics-placement="home_footer"
                >
                  <Icon name="download" />
                  <span>Download for Mac &mdash; free</span>
                </a>
                <ExternalLink className="btn btn--ghost btn--lg" href={RELEASES_URL}>
                  <Icon name="github" />
                  <span>All releases on GitHub</span>
                </ExternalLink>
              </div>
              <p className="get__meta">
                macOS 15.0 or later &middot; Apple Silicon (M1 or newer) &middot; no account required &middot;
                updates install in place.
                <br />
                Need it step by step? <Link className="link" href={GUIDE_PATH}>Read the Mac setup guide</Link>.
              </p>
            </div>

            <ol className="steps" id="install">
              <li>
                <b>01</b>
                <span>Open the <em>.dmg</em> and drag VoiceToText to Applications.</span>
              </li>
              <li>
                <b>02</b>
                <span>Grant <em>Microphone</em> and <em>Accessibility</em> when macOS asks.</span>
              </li>
              <li>
                <b>03</b>
                <span>Wait once while the default model downloads.</span>
              </li>
              <li>
                <b>04</b>
                <span>Press <HotkeyCombo /> anywhere and start talking.</span>
              </li>
            </ol>
          </div>
        </div>
      </div>
    </section>
  );
}
