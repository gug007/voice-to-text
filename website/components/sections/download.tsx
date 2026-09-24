import Image from "next/image";
import Link from "next/link";
import type { CSSProperties } from "react";

import { GUIDE_PATH, RELEASES_URL } from "@/lib/constants";
import { formatDisplayDate } from "@/lib/pages";
import type { LatestRelease } from "@/lib/release";
import { DownloadButton } from "@/components/ui/download-button";
import { ExternalLink } from "@/components/ui/external-link";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import { Icon } from "@/components/ui/icon";

const APP_ICON: CSSProperties = { borderRadius: "12px", marginBottom: "16px" };

export function Download({ release }: { release: LatestRelease }) {
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
                Free, source on GitHub, signed and notarized, and served from GitHub Releases. If it isn&rsquo;t
                for you, drag it to the Trash; its downloaded models and History stay in ~/Library/Application
                Support until you delete them. With the default local model, nothing you said left your Mac.
              </p>
              <div className="get__cta">
                <DownloadButton placement="home_download" />
                <ExternalLink
                  className="btn btn--ghost btn--lg"
                  href={RELEASES_URL}
                  data-analytics-event="github_outbound"
                  data-analytics-placement="home_download"
                >
                  <Icon name="github" />
                  <span>All releases on GitHub</span>
                </ExternalLink>
              </div>
              <p className="get__meta">
                {release.tag} &middot; released{" "}
                <time dateTime={release.publishedAt}>{formatDisplayDate(release.publishedAt)}</time> &middot;{" "}
                <ExternalLink
                  className="link"
                  href={release.url}
                  data-analytics-event="github_outbound"
                  data-analytics-placement="home_download_release"
                >
                  Release notes
                </ExternalLink>{" "}
                <br />
                macOS 15.0 or later &middot; Apple Silicon (M1 or newer) &middot; no account &middot; updates
                install when you confirm them.
              </p>
            </div>

            <div>
              <h3 className="get__steps-h">After you download</h3>
              <ol className="steps" id="install">
                <li>
                  <b>01</b>
                  <span>Open <em>VoiceToText.dmg</em>.</span>
                </li>
                <li>
                  <b>02</b>
                  <span>Drag VoiceToText to <em>Applications</em> and open it.</span>
                </li>
                <li>
                  <b>03</b>
                  <span>
                    Allow <em>Microphone</em> and <em>Accessibility</em> when macOS asks. The default model
                    downloads once.
                  </span>
                </li>
                <li>
                  <b>04</b>
                  <span>Press <HotkeyCombo /> in any app and start talking.</span>
                </li>
              </ol>
              <p className="get__guide">
                Need it step by step? <Link className="link" href={GUIDE_PATH}>Read the Mac setup guide</Link>.
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
